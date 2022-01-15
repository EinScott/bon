using System;
using System.Diagnostics;
using System.Reflection;
using System.Collections;

namespace Bon.Integrated
{
	static class Deserialize
	{
		public static mixin Error(BonReader reader, String error)
		{
#if (DEBUG || TEST) && !BON_NO_PRINT
			PrintError(reader, error);
#endif
			return .Err(default);
		}

		static void PrintError(BonReader reader, String error)
		{
			let err = scope $"BON ERROR: {error}. ";
			reader.GetCurrentPos(err);
#if TEST
			Console.WriteLine(err);
#else
			Debug.WriteLine(err);
#endif
		}

		static void MakeDefault(ref Variant val)
		{
			let valType = val.VariantType;
			if (valType.IsObject || valType.IsPointer)
			{
				// TODO
			}

			Internal.MemSet(val.DataPtr, 0, val.VariantType.Size);
		}

		public static Result<void> Thing(BonReader reader, ref Variant val, BonEnvironment env)
		{
			Try!(reader.ConsumeEmpty());

			if (reader.ReachedEnd())
				MakeDefault(ref val);
			else
			{
				Try!(Value(reader, ref val, env));

				if (!reader.ReachedEnd())
					Error!(reader, "Unexpected end");
			}
			return .Ok;
		}

		public static Result<void> Value(BonReader reader, ref Variant val, BonEnvironment env)
		{
			Type valType = val.VariantType;

			if (valType.IsPrimitive)
			{
				if (valType.IsInteger)
					Integer!(valType, reader, ref val);
				else if (valType.IsFloatingPoint)
					Float!(valType, reader, ref val);
				else if (valType.IsChar)
					Char!(valType, reader, ref val);
				else if (valType == typeof(bool))
					Bool!(reader, ref val);
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{
				mixin ParseUnderlyingLiteral(ref Variant parseVal)
				{
					if (valType.UnderlyingType.IsInteger)
						Integer!(valType.UnderlyingType, reader, ref parseVal);
					else if (valType.UnderlyingType.IsFloatingPoint)
						Float!(valType.UnderlyingType, reader, ref parseVal);
					else if (valType.UnderlyingType.IsChar)
						Char!(valType.UnderlyingType, reader, ref parseVal);
					else if (valType.UnderlyingType == typeof(bool))
						Bool!(reader, ref parseVal);
					else Debug.FatalError(); // Should be unreachable
				}

				if (valType.IsEnum)
				{
					int64 enumValue = 0;
					repeat
					{
						reader.EnumNext();
						if (reader.EnumHasNamed())
						{
							let name = Try!(reader.EnumName());

							// Find field on enum
							bool found = false;
							for (var field in valType.GetFields())
								if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase)
									&& name == field.Name)
								{
									// Add value of enum case to current enum value
									enumValue |= *(int64*)&field.[Friend]mFieldData.[Friend]mData;
									found = true;
									break;
								}

							if (!found)
								Error!(reader, "Enum case not found");
						}
						else
						{
							int64 literalData = 0;
							var parseVal = Variant.CreateReference(val.VariantType, &literalData);
							ParseUnderlyingLiteral!(ref parseVal);
							enumValue |= literalData;
						}
					}
					while (reader.EnumHasMore());

					// Assign value
					switch (valType.Size)
					{
					case 1: *(uint8*)val.DataPtr = *(uint8*)&enumValue;
					case 2: *(uint16*)val.DataPtr = *(uint16*)&enumValue;
					case 4: *(uint32*)val.DataPtr = *(uint32*)&enumValue;
					case 8: *(uint64*)val.DataPtr = *(uint64*)&enumValue;
					default: Debug.FatalError(); // Should be unreachable
					}
				}
				else ParseUnderlyingLiteral!(ref val);
			}
			else if (valType.IsStruct)
			{
				if (valType == typeof(StringView))
				{
					if (reader.HasNull())
					{
						*(StringView*)val.DataPtr = default;
					}
					else
					{
						String parsedStr = scope .();
						Try!(reader.String(parsedStr));

						// TODO: provide allocation options

						//*(StringView*)val.DataPtr = parsedStr;
					}
				}
				else if (valType.IsEnum && valType.IsUnion)
				{
					if (!reader.EnumHasNamed())
						Error!(reader, "Expected enum union case name");
					let name = Try!(reader.EnumName());

					Variant unionPayload = default;
					uint64 unionDiscrIndex = 0;
					Variant discrVal = default;
					bool foundCase = false;
					for (var enumField in valType.GetFields())
					{
						if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumCase))
						{
							if (name == enumField.Name)
							{
								unionPayload = Variant.CreateReference(enumField.FieldType, val.DataPtr);
								
								foundCase = true;
								break;
							}
							
							unionDiscrIndex++;
						}
						else if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumDiscriminator))
						{
							let discrType = enumField.FieldType;
							Debug.Assert(discrType.IsInteger);
							discrVal = Variant.CreateReference(discrType, (uint8*)val.DataPtr + enumField.[Friend]mFieldData.mData);
						}
					}

					Debug.Assert(discrVal != default);

					if (!foundCase)
						Error!(reader, "Enum union case not found");

					mixin PutVal<T>() where T : var
					{
						*(T*)discrVal.DataPtr = *(T*)&unionDiscrIndex;
					}

					switch (discrVal.VariantType)
					{
					case typeof(int8): PutVal!<int8>();
					case typeof(int16): PutVal!<int16>();
					case typeof(int32): PutVal!<int32>();
					case typeof(int64): PutVal!<int64>();
					case typeof(int): PutVal!<int>();

					case typeof(uint8): PutVal!<uint8>();
					case typeof(uint16): PutVal!<uint16>();
					case typeof(uint32): PutVal!<uint32>();
					case typeof(uint64): PutVal!<uint64>();
					case typeof(uint): PutVal!<uint>();

					default: Debug.FatalError(); // Should be unreachable
					}

					Try!(Struct(reader, ref unionPayload, env));
				}
				else Try!(Struct(reader, ref val, env));
			}
			else if (valType is SizedArrayType)
			{
				if (reader.ArrayHasSizer())
				{
					Try!(reader.ArraySizer(true));

					// Ignore sizer content..
					// we could do some checking, but erroring would be a bit harsh?
				}

				let t = (SizedArrayType)valType;
				let count = t.ElementCount;
				
				Try!(reader.ArrayBlock());

				if (count > 0)
				{
					let arrType = t.UnderlyingType;
					var ptr = (uint8*)val.DataPtr;
					var i = 0;
					for (; i < count && reader.ArrayHasMore(); i++)
					{
						var arrVal = Variant.CreateReference(arrType, ptr);
						Try!(Value(reader, ref arrVal, env));

						if (reader.ArrayHasMore())
							Try!(reader.EntryEnd());

						ptr += arrType.Stride;
					}

					// Default unaffected entries (since they aren't serialized)
					for (let j < count - i)
					{
						var arrVal = Variant.CreateReference(arrType, ptr);
						MakeDefault(ref arrVal);

						ptr += arrType.Stride;
					}
				}
				if (reader.ArrayHasMore())
					Error!(reader, "Sized array cannot fit element");

				Try!(reader.ArrayBlockEnd());
			}
			else if (valType.IsObject)
			{
				// TODO: for polymorphism we can't have this structure!
				// figure out if an explicit type is specified and get the type from it

				if (valType.IsBoxed)
				{
					Debug.FatalError();
				}
				else if (valType == typeof(String))
				{
					if (reader.HasNull())
					{
						if (*(String*)val.DataPtr != null)
						{
							let str = val.Get<String>();
							// TODO: option to delete string or do nothing
							// something like .ManageAllocations ??

							str.Clear();
						}
					}
					else
					{
						String parsedStr = scope .();
						Try!(reader.String(parsedStr));

						if (*(String*)val.DataPtr != null)
						{
							let str = val.Get<String>();
							str.Set(parsedStr);
						}
						else Debug.FatalError(); // TODO
					}
				}
				else if (valType is ArrayType)
				{
					Debug.FatalError();
				}
				else if (let t = valType as SpecializedGenericType && t == typeof(List<>))
				{
					Debug.FatalError();
				}
				else if (let t = valType as SpecializedGenericType && t == typeof(HashSet<>))
				{
					Debug.FatalError();
				}
				else if (let t = valType as SpecializedGenericType && t == typeof(Dictionary<,>))
				{
					Debug.FatalError();
				}
				// TODO: more builtin? maybe with custom handlers!
				else Try!(Class(reader, ref val, env));
			}
			else if (valType.IsPointer)
			{
				Debug.FatalError(); // TODO
			}
			else Debug.FatalError();

			return .Ok;
		}

		public static Result<void> Class(BonReader reader, ref Variant val, BonEnvironment env)
		{
			let classType = val.VariantType;

			Debug.Assert(classType.IsObject);

			let classPtr = (void**)val.DataPtr;
			if (reader.HasNull() && classPtr != null)
			{
				
			}
			else
			{
				// TODO: we might need to edit classType based on poylmorphism info
				// we read?

				// TODO: do ... based on env!
				if (classPtr == null)
				{
					// TODO: alloc
				}
				else
				{
					// TODO: make sure this is the type we want, otherwise realloc
				}

				var classDataVal = Variant.CreateReference(classType, *classPtr);
				Try!(Struct(reader, ref classDataVal, env));
			}

			return .Ok;
		}

		public static Result<void> Struct(BonReader reader, ref Variant val, BonEnvironment env)
		{
			let structType = val.VariantType;
			Try!(reader.ObjectBlock());

			List<FieldInfo> fields = scope .(structType.FieldCount);
			for (let f in structType.GetFields())
				fields.Add(f);

			while (reader.ObjectHasMore())
			{
				let name = Try!(reader.Identifier());

				FieldInfo fieldInfo = ?;
				bool found = false;
				for (let f in fields)
				{
					if (f.Name == name)
					{
						found = true;
						fieldInfo = f;
						@f.Remove();
						break;
					}
				}
				if (!found)
					Error!(reader, "Failed to find field");

				Variant fieldVal = Variant.CreateReference(fieldInfo.FieldType, ((uint8*)val.DataPtr) + fieldInfo.MemberOffset);

				Try!(Value(reader, ref fieldVal, env));

				if (reader.ObjectHasMore())
					Try!(reader.EntryEnd());
			}

			for (let f in fields)
			{
				Variant fieldVal = Variant.CreateReference(f.FieldType, ((uint8*)val.DataPtr) + f.MemberOffset);
				MakeDefault(ref fieldVal);
			}

			return reader.ObjectBlockEnd();
		}

		static mixin ParseThing<T>(BonReader reader, StringView num) where T : var
		{
			T thing = default;
			if (!(T.Parse(.(&num[0], num.Length)) case .Ok(out thing)))
				return Error!(reader, scope $"Failed to parse {typeof(T)}");
			thing
		}

		static mixin DoInt<T, T2>(BonReader reader, StringView numStr) where T2 : var where T : var
		{
			// Not all ints have parse methods (that also filter out letters properly), 
			// so we need to do this, along with range checks!

			T2 num = ParseThing!<T2>(reader, numStr);
#unwarn
			if (num > (T2)T.MaxValue || num < (T2)T.MinValue)
				return Error!(reader, scope $"Integer is out of range for {typeof(T)}");
			(T)num
		}

		static mixin Integer(Type type, BonReader reader, ref Variant val)
		{
			let num = Try!(reader.Integer());

			// TODO: make a custom parsing func like uint64 to properly parse hex; then allow hex in reader.Integer()
			// also support binary, as well as _ as separation (also check theoretical range of input even against uint64!)

			switch (type)
			{
			case typeof(int8): *(int8*)val.DataPtr = DoInt!<int8, int64>(reader, num);
			case typeof(int16): *(int16*)val.DataPtr = DoInt!<int16, int64>(reader, num);
			case typeof(int32): *(int32*)val.DataPtr = DoInt!<int32, int64>(reader, num);
			case typeof(int64): *(int64*)val.DataPtr = ParseThing!<int64>(reader, num);
			case typeof(int):
				if (sizeof(int) == 8)
					*(int*)val.DataPtr = ParseThing!<int64>(reader, num);
				else *(int*)val.DataPtr = DoInt!<int32, int64>(reader, num);

			case typeof(uint8): *(uint8*)val.DataPtr = DoInt!<uint8, uint64>(reader, num);
			case typeof(uint16): *(uint16*)val.DataPtr = DoInt!<uint16, uint64>(reader, num);
			case typeof(uint32): *(uint32*)val.DataPtr = DoInt!<uint32, uint64>(reader, num);
			case typeof(uint64): *(uint64*)val.DataPtr = ParseThing!<uint64>(reader, num);
			case typeof(uint):
				if (sizeof(uint) == 8)
					*(uint*)val.DataPtr = ParseThing!<uint64>(reader, num);
				else *(uint*)val.DataPtr = DoInt!<uint32, uint64>(reader, num);
			}
		}

		static mixin Float(Type type, BonReader reader, ref Variant val)
		{
			let num = Try!(reader.Floating());

			switch (type)
			{
			case typeof(float): *(float*)val.DataPtr = ParseThing!<float>(reader, num);
			case typeof(double): *(double*)val.DataPtr = ParseThing!<double>(reader, num);
			}
		}

		static mixin Char(Type type, BonReader reader, ref Variant val)
		{
			var char = Try!(reader.Char());

			switch (type)
			{
			case typeof(char8): *(char8*)val.DataPtr = *(char8*)&char;
			case typeof(char16): *(char16*)val.DataPtr = *(char16*)&char;
			case typeof(char32): *(char32*)val.DataPtr = *(char32*)&char;
			}
		}

		static mixin Bool(BonReader reader, ref Variant val)
		{
			let b = Try!(reader.Bool());

			*(bool*)val.DataPtr = b;
		}
	}
}