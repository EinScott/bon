using System;
using System.Diagnostics;
using System.Reflection;
using System.Collections;

using internal Bon;
using internal Bon.Integrated;

#if (DEBUG || TEST) && !BON_NO_PRINT
#define BON_PRINT
#endif

namespace Bon.Integrated
{
	static class Deserialize
	{
		public static mixin Error(BonReader reader, String error)
		{
#if BON_PRINT
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

		public static mixin Error(Type type, String error)
		{
#if BON_PRINT
			PrintError(type, error);
#endif
			return .Err(default);
		}

		static void PrintError(Type type, String error)
		{
			let err = scope $"BON ERROR: {error}.\nOn type: ";
			type.ToString(err);
#if TEST
			Console.WriteLine(err);
#else
			Debug.WriteLine(err);
#endif
		}

		static void MakeDefault(ref Variant val, BonEnvironment env)
		{
			if (VariantDataIsZero!(val))
				return;

			let valType = val.VariantType;
			if (valType.IsObject || valType.IsPointer)
			{
				if (env.instanceHandlers.TryGetValue(val.VariantType, let funcs)
					&& funcs.destroy != null)
				{
					funcs.destroy(val);
				}
				else
				{
					if (valType.IsPointer)
						delete *(void**)val.DataPtr;
					else delete Internal.UnsafeCastToObject(*(void**)val.DataPtr);
				}
			}

			let ptr = val.DataPtr;
			let size = val.VariantType.Size;
			switch (size)
			{
			case 0:
			case 1: *(uint8*)ptr = 0;
			case 2: *(uint16*)ptr = 0;
			case 4: *(uint32*)ptr = 0;
			case 8: *(uint64*)ptr = 0;
			default:
				Internal.MemSet(ptr, 0, size);
			}
		}

		public static Result<void> MakeInstanceRef(ref Variant val, BonEnvironment env)
		{
			let valType = val.VariantType;
			Debug.Assert(valType.IsObject || valType.IsPointer);

			if (env.instanceHandlers.TryGetValue(val.VariantType, let funcs)
				&& funcs.make != null)
			{
				funcs.make(val);
			}
			else
			{
				// TODO: some way to generally change memory allocation method?
				// something in bonEnv... also copy & edit CreateObject to use that
				// -> maybe go the string/list route and just make overridable
				// alloc / delete methods on BonEnv?

				if (val.VariantType.IsPointer)
				{
					Debug.FatalError();
					// TODO: allocate uint8[Size]
					// but check how to get the actual size from the pointer type
					// is it UnderlyingType? is it InstanceSize?
				}
				else
				{
					void* objRef;
					if (val.VariantType.CreateObject() case .Ok(let createdObj))
						objRef = Internal.UnsafeCastToPtr(createdObj);
					else Error!(val.VariantType, "Failed to create object");

					*((void**)val.DataPtr) = objRef;
				}
			}

			return .Ok;
		}

		public static Result<BonContext> Thing(BonReader reader, ref Variant val, BonEnvironment env)
		{
			Try!(reader.ConsumeEmpty());

			if (reader.ReachedEnd())
				Error!(reader, "Expected entry");
			else
			{
				if (reader.IsIrrelevantEntry())
				{
					if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
						MakeDefault(ref val, env);

					Try!(reader.ConsumeEmpty());
				}
				else Try!(Value(reader, ref val, env));

				if (!reader.ReachedEnd() && !reader.FileHasMore(false))
					Error!(reader, "Expected entry end");
			}

			// Remove ',' between this and possibly the next entry
			let hasMore = reader.FileHasMore();

			// Pass state on
			let context = BonContext{
				strLeft = reader.inStr,
				origStr = reader.origStr,
				hasMore = hasMore
			};

			return .Ok(context);
		}

		public static Result<void> Value(BonReader reader, ref Variant val, BonEnvironment env)
		{
			let valType = val.VariantType;
			var polyType = valType;

			if (reader.IsTyped())
			{
				if (TypeHoldsObject!(valType))
				{
					let typeName = reader.Type();

					if (env.polyTypes.TryGetValue(scope .(typeName), let type))
					{
						if (valType.IsInterface)
						{
							if (!type.HasInterface(valType))
								Error!(reader, scope $"Specified type does not implement {valType}");
						}
						else if (type.IsObject /* boxed structs or primitives */ && !type.IsSubtypeOf(valType))
							Error!(reader, scope $"Specified type is not a sub-type of {valType}");

						// Store it but don't apply it, so that we still easily
						// select the IsObject case even for boxed structs
						polyType = type;
					}
					else if (typeName != (StringView)valType.GetFullName(.. scope .())) // It's the base type itself, and we got that!
						Error!(reader, "Specified type not found in bonEnvironment.polyTypes");
				}
				else Error!(reader, "Type markers are only valid on reference types");
			}

			if (reader.IsDefault())
				MakeDefault(ref val, env);
			else if (reader.IsIrrelevantEntry())
				Error!(reader, "Ignored is only valid in arrays");
			else if (valType.IsPrimitive)
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
					if (reader.IsNull())
					{
						*(StringView*)val.DataPtr = default;
					}
					else
					{
						String parsedStr = scope .();
						Try!(reader.String(parsedStr));

						if (env.stringViewHandler != null)
						{
							let str = env.stringViewHandler(parsedStr);
							Debug.Assert(str.Ptr != parsedStr.Ptr, "[BON ENV] Seriously? bonEnvironment.stringViewHandler returned passed in view but should manage the string's memory!");
							Debug.Assert(str == parsedStr, "[BON ENV] bonEnvironment.stringViewHandler returned altered string!");

							*(StringView*)val.DataPtr = str;
						}
						else Debug.FatalError("[BON ENV] Register a bonEnvironment.stringViewHandler to deserialize StringViews!");
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

						if (reader.IsIrrelevantEntry())
						{
							// Null unless we leave these alone!
							if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
								MakeDefault(ref arrVal, env);
						}
						else Try!(Value(reader, ref arrVal, env));

						if (reader.ArrayHasMore())
							Try!(reader.EntryEnd());

						ptr += arrType.Stride;
					}

					if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
					{
						// Default unaffected entries (since they aren't serialized)
						for (let j < count - i)
						{
							var arrVal = Variant.CreateReference(arrType, ptr);
							MakeDefault(ref arrVal, env);

							ptr += arrType.Stride;
						}
					}
				}
				if (reader.ArrayHasMore())
					Error!(reader, "Sized array cannot fit element");

				Try!(reader.ArrayBlockEnd());
			}
			else if (TypeHoldsObject!(valType))
			{
				if (reader.IsNull())
				{
					if (*(void**)val.DataPtr != null)
						MakeDefault(ref val, env);
				}
				else
				{
					if (!polyType.IsObject)
					{
						Debug.Assert(valType != polyType);

						let boxType = polyType.BoxedType;
						if (boxType != null)
						{
							// Current reference is of a different type, so clean
							// it up to make our type instance below
							if (*(void**)val.DataPtr != null
								&& (*(Object*)val.DataPtr).GetType() != polyType) // Box still returns type of boxed
								MakeDefault(ref val, env);

							val.UnsafeSetType(boxType);

							if (*(void**)val.DataPtr == null)
								Try!(MakeInstanceRef(ref val, env));

							let boxedPtr = (uint8*)*(void**)val.DataPtr + sizeof(int) // mClassVData
#if BF_DEBUG_ALLOC
								+ sizeof(int) // mDebugAllocInfo
#endif
								;

							var boxedData = Variant.CreateReference(polyType, boxedPtr);
							Try!(Value(reader, ref boxedData, env));
						}
						else Error!(reader, "Failed to access boxed type");
					}
					else
					{
						if (polyType != valType)
						{
							// Current reference is of a different type, so clean
							// it up to make our type instance below
							if (*(void**)val.DataPtr != null
								&& (*(Object*)val.DataPtr).GetType() != polyType)
								MakeDefault(ref val, env);

							val.UnsafeSetType(polyType);
						}
						else Debug.Assert(!valType.IsInterface);

						if (*(void**)val.DataPtr == null)
							Try!(MakeInstanceRef(ref val, env));

						if (polyType == typeof(String))
						{
							String parsedStr = scope .();
							Try!(reader.String(parsedStr));

							var str = *(String*)(void**)val.DataPtr;

							str.Set(parsedStr);
						}
						else Try!(Class(reader, ref val, env));
					}
				}
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

			var classDataVal = Variant.CreateReference(classType, *(void**)val.DataPtr);
			Try!(Struct(reader, ref classDataVal, env));

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

			if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
			{
				for (let f in fields)
				{
					Variant fieldVal = Variant.CreateReference(f.FieldType, ((uint8*)val.DataPtr) + f.MemberOffset);
					MakeDefault(ref fieldVal, env);
				}
			}

			return reader.ObjectBlockEnd();
		}

		static mixin ParseThing<T>(BonReader reader, StringView num) where T : var
		{
			T thing = default;
			if (!(T.Parse(.(&num[0], num.Length)) case .Ok(out thing)))
				Error!(reader, scope $"Failed to parse {typeof(T)}");
			thing
		}

		static mixin DoInt<T, T2>(BonReader reader, StringView numStr) where T2 : var where T : var
		{
			// Not all ints have parse methods (that also filter out letters properly), 
			// so we need to do this, along with range checks!

			T2 num = ParseThing!<T2>(reader, numStr);
#unwarn
			if (num > (T2)T.MaxValue || num < (T2)T.MinValue)
				Error!(reader, scope $"Integer is out of range for {typeof(T)}");
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

		static mixin DoChar<T, TI>(BonReader reader, ref Variant val, char32 char) where T : var where TI : var
		{
			if ((uint)char > TI.MaxValue)
				Error!(reader, scope $"Char is out of range for {typeof(T)}");

			*(T*)val.DataPtr = *(T*)&char;
		}

		static mixin Char(Type type, BonReader reader, ref Variant val)
		{
			var char = Try!(reader.Char());

			// @report: just putting "mixin DO" here perma hardcrashes.. stackoverflow?!
			
			switch (type)
			{
			case typeof(char8): DoChar!<char8, uint8>(reader, ref val, char);
			case typeof(char16): DoChar!<char16, uint16>(reader, ref val, char);
			case typeof(char32): DoChar!<char32, uint32>(reader, ref val, char);
			}
		}

		static mixin Bool(BonReader reader, ref Variant val)
		{
			let b = Try!(reader.Bool());

			*(bool*)val.DataPtr = b;
		}
	}
}