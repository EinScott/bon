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
			Debug.Assert(!valType.IsArray && (valType.IsObject || valType.IsPointer));

			if (env.instanceHandlers.TryGetValue(val.VariantType, let funcs)
				&& funcs.make != null)
			{
				funcs.make(val);
			}
			else
			{
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

		public static Result<void> MakeArrayInstanceRef(ref Variant val, int32 count)
		{
			Debug.Assert(val.VariantType.IsArray);
			let valType = (ArrayType)val.VariantType;

			// No way to do this in a custom way currently, since we'd have to pass count there
			// too. Technically possible, but not for now.

			void* objRef;
			if (valType.CreateObject(count) case .Ok(let createdObj))
				objRef = Internal.UnsafeCastToPtr(createdObj);
			else Error!(val.VariantType, "Failed to create array");

			*((void**)val.DataPtr) = objRef;

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

				if (!reader.ReachedEnd())
				{
					// Remove ',' between this and possibly the next entry
					// Checks are restricted to this file entry, everything after the comma is not our business.
					Try!(reader.FileEntryEnd());
				}
			}

			// Pass state on
			return .Ok(.(reader.origStr, reader.inStr));
		}

		public static Result<void> Value(BonReader reader, ref Variant val, BonEnvironment env)
		{
			let valType = val.VariantType;
			var polyType = valType;

			if (reader.IsTyped() || valType.IsInterface)
			{
				if (TypeHoldsObject!(valType))
				{
					let typeName = Try!(reader.Type());

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
				else Error!(reader, "Type markers are only valid on reference types and interfaces");
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
				else if (GetCustomHandler(valType, env, let func))
					Try!(func(reader, ref val, env));
				else Try!(Struct(reader, ref val, env));
			}
			else if (valType is SizedArrayType)
			{
				if (reader.ArrayHasSizer())
				{
					Try!(reader.ArraySizer<const 1>(true));

					// Ignore sizer content..
					// we could do some checking, but erroring would be a bit harsh?
				}

				let t = (SizedArrayType)valType;
				Try!(Array(reader, t.UnderlyingType, val.DataPtr, t.ElementCount, env));
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

							// Throw together the pointer to the box payload
							// in the corlib approved way. (See Variant.CreateFromBoxed)
							let boxedPtr = (uint8*)*(void**)val.DataPtr + boxType.[Friend]mMemberDataOffset;

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

						if (*(void**)val.DataPtr == null
							&& !polyType.IsArray) // Arrays handle it differently
							Try!(MakeInstanceRef(ref val, env));

						if (polyType == typeof(String))
						{
							var str = *(String*)(void**)val.DataPtr;

							str.Clear();
							String!(reader, ref str, env);
						}
						else if (polyType.IsArray) ARRAY:
						{
							Debug.Assert(polyType != typeof(Array) && polyType is ArrayType);

							let t = polyType as ArrayType;

							int_arsize fullCount = 0;
							int_arsize[] counts = null;
							switch (t.UnspecializedType)
							{
							case typeof(Array1<>):
								if (reader.ArrayHasSizer())
								{
									let sizer = Try!(reader.ArraySizer<const 1>(false));
									fullCount = Try!(ParseInt<int_arsize>(reader, sizer[0])); // We already check it's not negative
								}
								else
								{
									// We could do this in a more complicated manner for multi-dim arrays, just
									// getting the max for each dimension, but why not just use an array of other
									// arrays in that case? It's probably sensible for multi-dim arrays to state
									// their size upfront!

									fullCount = (.)Try!(reader.ArrayPeekCount());
								}

							case typeof(Array2<>):
								let sizer = Try!(reader.ArraySizer<const 2>(false));
								counts = scope:ARRAY .[2];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));

								fullCount = counts[0] * counts[1];

							case typeof(Array3<>):
								let sizer = Try!(reader.ArraySizer<const 3>(false));
								counts = scope:ARRAY .[3];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));
								counts[2] = Try!(ParseInt<int_arsize>(reader, sizer[2]));

								fullCount = counts[0] * counts[1] * counts[2];

							case typeof(Array4<>):
								let sizer = Try!(reader.ArraySizer<const 4>(false));
								counts = scope:ARRAY .[4];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));
								counts[2] = Try!(ParseInt<int_arsize>(reader, sizer[2]));
								counts[3] = Try!(ParseInt<int_arsize>(reader, sizer[3]));

								fullCount = counts[0] * counts[1] * counts[2] * counts[3];

							default:
								Debug.FatalError();
							}

							// Deallocate old array if count doesn't match
							if (*(void**)val.DataPtr != null)
							{
								let currCount = val.Get<Array>().Count;
								if (fullCount != currCount)
									MakeDefault(ref val, env);
							}

							if (*(void**)val.DataPtr == null)
							{
								// We're screwed on big collections, but who uses that...? hah
								Try!(MakeArrayInstanceRef(ref val, (int32)fullCount));
							}
							Debug.Assert(val.Get<Array>().Count == fullCount);

							let arrType = t.GetGenericArg(0); // T
							let classData = *(uint8**)val.DataPtr;

							void* arrPtr = null;
							if (t.GetField("mFirstElement") case .Ok(let field))
								arrPtr = classData + field.MemberOffset; // T*
							else Error!(t, "No reflection data forced for array type!"); // for example: [Serializable] extension Array1<T> {} or through build settings

							switch (t.UnspecializedType)
							{
							case typeof(Array4<>):
								SetValField!(classData, t, "mLength3", counts[3]);
								fallthrough;
							case typeof(Array3<>):
								SetValField!(classData, t, "mLength2", counts[2]);
								fallthrough;
							case typeof(Array2<>):
								SetValField!(classData, t, "mLength1", counts[1]);

								Try!(MultiDimensionalArray(reader, arrType, arrPtr, env, params counts));

							case typeof(Array1<>):
								Try!(Array(reader, arrType, arrPtr, fullCount, env));

							default:
								Debug.FatalError();
							}
						}
						else if (GetCustomHandler(polyType, env, let func))
							Try!(func(reader, ref val, env));
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

		static bool GetCustomHandler(Type type, BonEnvironment env, out HandleDeserializeFunc func)
		{
			if (env.serializeHandlers.TryGetValue(type, let val) && val.deserialize != null)
			{
				func = val.deserialize;
				return true;
			}
			else if (type is SpecializedGenericType && env.serializeHandlers.TryGetValue(((SpecializedGenericType)type).UnspecializedType, let gVal)
				&& gVal.deserialize != null)
			{
				func = gVal.deserialize;
				return true;
			}
			func = null;
			return false;
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

		public static Result<void> Array(BonReader reader, Type arrType, void* arrPtr, int64 count, BonEnvironment env)
		{
			Try!(reader.ArrayBlock());

			if (count > 0)
			{
				var ptr = (uint8*)arrPtr;
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
					if (arrType.IsValueType)
						Internal.MemSet(ptr, 0, arrType.Stride * ((int)count - i)); // MakeDefault would just do the same here
					else
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
			}
			if (reader.ArrayHasMore())
				Error!(reader, "Array cannot fit element");

			return reader.ArrayBlockEnd();
		}

		public static Result<void> MultiDimensionalArray(BonReader reader, Type arrType, void* arrPtr, BonEnvironment env, params int_arsize[] counts)
		{
			Debug.Assert(counts.Count > 1); // Must be multi-dimensional!

			let count = counts[0];
			var stride = counts[1];
			if (counts.Count > 2)
				for (let i < counts.Count - 2)
					stride *= counts[i + 2];
			stride *= arrType.Stride;

			mixin DefaultArray(void* ptr)
			{
				let inner = counts.Count - 1;
				if (inner > 1)
				{
					int_arsize[] innerCounts = scope .[inner];
					for (let j < inner)
						innerCounts[j] = counts[j + 1];

					DefaultMultiDimensionalArray(arrType, ptr, env, params innerCounts);
				}
				else DefaultArray(arrType, ptr, counts[1], env);
			}

			Try!(reader.ArrayBlock());

			if (count > 0)
			{
				var ptr = (uint8*)arrPtr;
				var i = 0;
				for (; i < count && reader.ArrayHasMore(); i++)
				{
					// Since we don't call value in any case, we have to check for this ourselves
					let isDefault = reader.IsDefault();
					if (isDefault || reader.IsIrrelevantEntry())
					{
						// Null unless we leave these alone!
						if (isDefault || !env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
						{
							if (arrType.IsValueType)
								Internal.MemSet(ptr, 0, stride); // MakeDefault would just do the same here
							else DefaultArray!(ptr);
						}

						Try!(reader.ConsumeEmpty());
					}
					else
					{
						let inner = counts.Count - 1;
						if (inner > 1)
						{
							int_arsize[] innerCounts = scope .[inner];
							for (let j < inner)
								innerCounts[j] = counts[j + 1];

							Try!(MultiDimensionalArray(reader, arrType, ptr, env, params innerCounts));
						}
						else Try!(Array(reader, arrType, ptr, counts[1], env));
					}

					if (reader.ArrayHasMore())
						Try!(reader.EntryEnd());

					ptr += stride;
				}

				if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
				{
					if (arrType.IsValueType)
						Internal.MemSet(ptr, 0, stride * (count - i)); // MakeDefault would just do the same here
					else
					{
						// Default unaffected entries (since they aren't serialized)
						for (let j < count - i)
						{
							DefaultArray!(ptr);

							ptr += stride;
						}
					}
				}
			}
			if (reader.ArrayHasMore())
				Error!(reader, "Array cannot fit element");

			return reader.ArrayBlockEnd();
		}

		public static void DefaultArray(Type arrType, void* arrPtr, int_arsize count, BonEnvironment env)
		{
			var ptr = (uint8*)arrPtr;
			for (let j < count)
			{
				var arrVal = Variant.CreateReference(arrType, ptr);
				MakeDefault(ref arrVal, env);

				ptr += arrType.Stride;
			}
		}

		public static void DefaultMultiDimensionalArray(Type arrType, void* arrPtr, BonEnvironment env, params int_arsize[] counts)
		{
			Debug.Assert(counts.Count > 1); // Must be multi-dimensional!

			let count = counts[0];
			var stride = counts[1];
			if (counts.Count > 2)
				for (let i < counts.Count - 2)
					stride *= counts[i + 2];
			stride *= arrType.Stride;

			if (count > 0)
			{
				var ptr = (uint8*)arrPtr;
				
				for (let i < count)
				{
					let inner = counts.Count - 1;
					if (inner > 1)
					{
						int_arsize[] innerCounts = scope .[inner];
						for (let j < inner)
							innerCounts[j] = counts[j + 1];

						DefaultMultiDimensionalArray(arrType, ptr, env, params innerCounts);
					}
					else DefaultArray(arrType, ptr, counts[1], env);

					ptr += stride;
				}
			}
		}

		public static mixin String(BonReader reader, ref String parsedStr, BonEnvironment env)
		{
			let isSubfile = reader.IsSubfile();
			int len = 0;
			bool isVerbatim = false;
			if (isSubfile)
				len = Try!(reader.SubfileStringLength());
			else (len, isVerbatim) = Try!(reader.StringLength());
			Debug.Assert(len >= 0);

			if (parsedStr == null)
				parsedStr = scope:mixin .(len);

			if (isSubfile)
				Try!(reader.SubfileString(parsedStr, len));
			else Try!(reader.String(parsedStr, len, isVerbatim));
		}

		public static Result<T> ParseInt<T>(BonReader reader, StringView val, bool allowNonDecimal = true) where T : IInteger, var
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