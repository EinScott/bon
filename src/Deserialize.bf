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
			{
				MakeDefault(ref val, env);

				Try!(reader.ConsumeEmpty());
			}	
			else if (reader.IsIrrelevantEntry())
				Error!(reader, "Ignored markers are only valid in arrays");
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

						Try!(reader.ConsumeEmpty());
					}
					else
					{
						String parsedStr = null;
						String!(reader, ref parsedStr, env);

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

							Try!(reader.ConsumeEmpty());
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

					Try!(reader.ConsumeEmpty());
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
							var str = *(String*)(void**)val.DataPtr;

							str.Clear();
							String!(reader, ref str, env);
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

		public static mixin String(BonReader reader, ref String parsedStr, BonEnvironment env)
		{
			let isSubfile = reader.IsSubfile();
			int len = 0;
			if (isSubfile)
				len = Try!(reader.SubfileStringLength());
			else len = Try!(reader.StringLength());
			Debug.Assert(len >= 0);

			if (parsedStr == null)
				parsedStr = scope:mixin .(len);

			if (isSubfile)
				Try!(reader.SubfileString(parsedStr, len));
			else Try!(reader.String(parsedStr, len));
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

		static Result<T> ParseInt<T>(BonReader reader, StringView val, bool allowNonDecimal = true) where T : IInteger, var
		{
			var len = val.Length;
			if (len == 0)
				return .Err;

			uint64 prevRes = 0;
			uint64 result = 0;
			bool isNegative = false;
			bool allowBaseSpec = false;
			uint64 radix = 10;
			int digits = 0;

			for (var i = 0; i < len; i++)
			{
				let c = val[[Unchecked]i];

				if ((c == '0') || (c == '1'))
				{
					if (digits == 0 && c == '0')
					{
						allowBaseSpec = true;
						continue;
					}
					result = result*radix + (.)(c - '0');
				}
				else if (radix > 0b10 && (c >= '2') && (c <= '7')
					|| radix > 0o10 && ((c == '8') || (c == '9')))
					result = result*radix + (.)(c - '0');
				else if (radix > 10 && (c >= 'A') && (c <= 'F'))
					result = result*radix + (.)(c - 'A') + 10;
				else if (radix > 10 && (c >= 'a') && (c <= 'f'))
					result = result*radix + (.)(c - 'a') + 10;
				else if (digits == 0 && allowBaseSpec)
				{
					switch (c)
					{
					case 'x': radix = 0x10;
					case 'b': radix = 0b10;
					case 'o': radix = 0o10;
					}
					allowBaseSpec = false;
					continue;
				}
				else if (digits == 0 && c == '-' && typeof(T).IsSigned)
				{
					isNegative = true;
					continue;
				}
				else if (c == '\'')
					continue;
				else Error!(reader, scope $"Failed to parse {typeof(T)}");

				digits++;

				if (result < prevRes)
					Error!(reader, scope $"Integer is out of range for {typeof(T)}");
				prevRes = result;
			}

			// Check overflow
			if (isNegative)
			{
				if (result > int64.MaxValue)
					Error!(reader, scope $"Integer is out of range for {typeof(T)}");
				let num = -(*(int64*)&result);
				if (num < (int64)T.MinValue || num > (int64)T.MaxValue)
					Error!(reader, scope $"Integer is out of range for {typeof(T)}");
				else return .Ok((T)num);
			}
			else
			{
				let num = result;
				if (result > (uint64)T.MaxValue)
					Error!(reader, scope $"Integer is out of range for {typeof(T)}");
				else return .Ok((T)num);
			}
		}

		static mixin ParseThing<T>(BonReader reader, StringView num) where T : var
		{
			T thing = default;
			if (!(T.Parse(.(&num[0], num.Length)) case .Ok(out thing)))
				Error!(reader, scope $"Failed to parse {typeof(T)}");
			thing
		}

		static mixin Integer(Type type, BonReader reader, ref Variant val)
		{
			let num = Try!(reader.Integer());

			switch (type)
			{
			case typeof(int8): *(int8*)val.DataPtr = Try!(ParseInt<int8>(reader, num));
			case typeof(int16): *(int16*)val.DataPtr = Try!(ParseInt<int16>(reader, num));
			case typeof(int32): *(int32*)val.DataPtr = Try!(ParseInt<int32>(reader, num));
			case typeof(int64): *(int64*)val.DataPtr = Try!(ParseInt<int64>(reader, num));
			case typeof(int): *(int*)val.DataPtr = Try!(ParseInt<int>(reader, num));

			case typeof(uint8): *(uint8*)val.DataPtr = Try!(ParseInt<uint8>(reader, num));
			case typeof(uint16): *(uint16*)val.DataPtr = Try!(ParseInt<uint16>(reader, num));
			case typeof(uint32): *(uint32*)val.DataPtr = Try!(ParseInt<uint32>(reader, num));
			case typeof(uint64): *(uint64*)val.DataPtr = Try!(ParseInt<uint64>(reader, num));
			case typeof(uint): *(uint*)val.DataPtr = Try!(ParseInt<uint>(reader, num));
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