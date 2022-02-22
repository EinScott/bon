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
		public static mixin Error(String error, BonReader reader, Type type = null)
		{
#if BON_PRINT || BON_PROVIDE_ERROR_MESSAGE
			ProcessMessage(error, reader, type);
#endif

			return .Err(default);
		}

		static void ProcessMessage(String error, BonReader reader, Type type)
		{
			let message = scope String(512);
			message.AppendF("BON ERROR: {}. ", error);
			if (reader != null)
				reader.GetCurrentPos(message);
			if (type != null)
				message.AppendF("\n> On type: {}", type);
#if BON_PRINT
#if TEST
			Console.WriteLine(message);
#else
			Debug.WriteLine(message);
#endif
#endif
#if BON_PROVIDE_ERROR_MESSAGE
			using (Bon.[Friend]errLock.Enter())
				if (Bon.onDeserializeError.HasListeners)
					Bon.onDeserializeError(message);
#endif
		}

		public static Result<void> MakeDefault(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (ValueDataIsZero!(val))
				return .Ok;

			Try!(CheckCanDefault(reader, val, env));

			let ptr = val.dataPtr;
			let size = val.type.Size;
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

			return .Ok;
		}

		public static Result<void> DefaultArray(BonReader reader, Type arrType, void* arrPtr, int64 count, BonEnvironment env)
		{
			var ptr = (uint8*)arrPtr;
			for (let j < count)
			{
				Try!(MakeDefault(reader, ValueView(arrType, ptr), env));

				ptr += arrType.Stride;
			}
			return .Ok;
		}

		public static Result<void> DefaultMultiDimensionalArray(BonReader reader, Type arrType, void* arrPtr, BonEnvironment env, params int64[] counts)
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
						int64[] innerCounts = scope .[inner];
						for (let j < inner)
							innerCounts[j] = counts[j + 1];

						Try!(DefaultMultiDimensionalArray(reader, arrType, ptr, env, params innerCounts));
					}
					else Try!(DefaultArray(reader, arrType, ptr, counts[1], env));

					ptr += stride;
				}
			}
			return .Ok;
		}

		public static Result<void> CheckCanDefault(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (ValueDataIsZero!(val))
				return .Ok;

			let valType = val.type;
			if (valType.IsStruct)
			{
				if (!env.deserializeFlags.HasFlag(.AllowReferenceNulling))
					Try!(CheckStructForRef(reader, val, env));
			}
			else if (valType is SizedArrayType)
			{
				let t = (SizedArrayType)valType;
				let arrType = t.UnderlyingType;
				let count = t.ElementCount;
				var ptr = (uint8*)val.dataPtr;

				for (let j < count)
				{
					Try!(CheckCanDefault(reader, ValueView(arrType, ptr), env));

					ptr += arrType.Stride;
				}
				return .Ok;
			}
			else if (TypeHoldsObject!(valType))
			{
				if (!env.deserializeFlags.HasFlag(.AllowReferenceNulling))
					Error!("Cannot null reference", reader, valType);
			}
			else if (valType.IsPointer)
			{
				if (!env.deserializeFlags.HasFlag(.IgnorePointers))
					Error!("Cannot handle pointer values", reader, valType);
			}

			return .Ok;
		}

		public static Result<void> CheckStructForRef(BonReader reader, ValueView val, BonEnvironment env)
		{
			let allowNulling = env.deserializeFlags.HasFlag(.AllowReferenceNulling);
			Debug.Assert(!allowNulling);

			for (let f in val.type.GetFields(.Instance))
			{
				let fieldType = f.FieldType;
				if (fieldType.IsStruct)
					Try!(CheckStructForRef(reader, ValueView(fieldType, (uint8*)val.dataPtr + f.MemberOffset), env));
				else if (TypeHoldsObject!(fieldType) && !allowNulling)
					Error!("Cannot null reference nested in struct", reader, fieldType);
				else if (val.type.IsPointer)
					Error!("Cannot handle pointer values nested in struct", reader, fieldType);
			}

			return .Ok;
		}

		[Inline]
		public static Result<void> NullInstanceRef(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (*(void**)val.dataPtr != null)
			{
				if (env.deserializeFlags.HasFlag(.AllowReferenceNulling))
				{
					*(void**)val.dataPtr = null;
					return .Ok;
				}

				Error!("Cannot null reference", reader, val.type);
			}

			return .Ok;
		}

		public static Result<void> MakeInstanceRef(BonReader reader, ValueView val, BonEnvironment env)
		{
			let valType = val.type;
			Debug.Assert(!valType.IsArray && (valType.IsObject));

			MakeThingFunc make = null;
			if (env.allocHandlers.TryGetValue(valType, let func)
				&& func != null)
				make = func;
			else if (valType is SpecializedGenericType && env.allocHandlers.TryGetValue(((SpecializedGenericType)valType).UnspecializedType, let gFunc)
				&& gFunc != null)
				make = gFunc;

			if (make != null)
				make(val);
			else
			{
				void* objRef;
				if (val.type.CreateObject() case .Ok(let createdObj))
					objRef = Internal.UnsafeCastToPtr(createdObj);
				else Error!("Failed to create object", null, val.type);

				*((void**)val.dataPtr) = objRef;
			}

			return .Ok;
		}

		public static Result<void> MakeArrayInstanceRef(ValueView val, int32 count)
		{
			Debug.Assert(val.type.IsArray);
			let valType = (ArrayType)val.type;

			// No way to do this in a custom way currently, since we'd have to pass count there
			// too. Technically possible, but not for now.

			void* objRef;
			if (valType.CreateObject(count) case .Ok(let createdObj))
				objRef = Internal.UnsafeCastToPtr(createdObj);
			else Error!("Failed to create array", null, val.type);

			*((void**)val.dataPtr) = objRef;

			return .Ok;
		}

		// These two are for integrated use!
		[Inline]
		public static Result<void> Start(BonReader reader)
		{
			Try!(reader.ConsumeEmpty());

			if (reader.ReachedEnd())
				Error!("Expected entry", reader);
			return .Ok;
		}

		[Inline]
		public static Result<BonContext> End(BonReader reader)
		{
			if (!reader.ReachedEnd())
			{
				// Remove ',' between this and possibly the next entry
				// Checks are restricted to this file entry, everything after the comma is not our business.
				Try!(reader.FileEntryEnd());
			}

			// Pass state on
			return .Ok(.(reader.origStr, reader.inStr));
		}

		public static Result<BonContext> Entry(BonReader reader, ValueView val, BonEnvironment env)
		{
			Try!(Start(reader));

			if (reader.IsIrrelevantEntry())
			{
				if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
					Try!(MakeDefault(reader, val, env));

				Try!(reader.ConsumeEmpty());
			}
			else Try!(Value(reader, val, env));

			return End(reader);
		}

		public static Result<void> Value(BonReader reader, ValueView val, BonEnvironment env)
		{
			let valType = val.type;
			var polyType = valType;

			if (reader.IsTyped() || valType.IsInterface)
			{
				if (TypeHoldsObject!(valType))
				{
					let typeName = Try!(reader.Type());

					if (env.TryGetPolyType(typeName, let type))
					{
						if (valType.IsInterface)
						{
							if (!type.HasInterface(valType))
								Error!(scope $"Specified type does not implement {valType}", reader, type);
						}
						else if (type.IsObject /* boxed structs or primitives */ && !type.IsSubtypeOf(valType))
							Error!(scope $"Specified type is not a sub-type of {valType}", reader, type);

						// Store it but don't apply it, so that we still easily
						// select the IsObject case even for boxed structs
						polyType = type;
					}
					else if (typeName != (StringView)valType.GetFullName(.. scope .())) // It's the base type itself, and we got that!
						Error!("Specified type not found in bonEnvironment.polyTypes", reader, valType);
				}
				else Error!("Type markers are only valid on reference types and interfaces", reader, valType);
			}

			if (reader.IsDefault())
			{
				Try!(MakeDefault(reader, val, env));

				Try!(reader.ConsumeEmpty());
			}	
			else if (reader.IsIrrelevantEntry())
				Error!("Ignored markers are only valid in arrays", reader);
			else if (valType.IsPrimitive)
			{
				if (valType.IsInteger)
					Integer!(valType, reader, val);
				else if (valType.IsFloatingPoint)
					Float!(valType, reader, val);
				else if (valType.IsChar)
					Char!(valType, reader, val);
				else if (valType == typeof(bool))
					Bool!(reader, val);
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{
				mixin ParseUnderlyingLiteral(ValueView parseVal)
				{
					if (valType.UnderlyingType.IsInteger)
						Integer!(valType.UnderlyingType, reader, parseVal);
					else if (valType.UnderlyingType.IsFloatingPoint)
						Float!(valType.UnderlyingType, reader, parseVal);
					else if (valType.UnderlyingType.IsChar)
						Char!(valType.UnderlyingType, reader, parseVal);
					else if (valType.UnderlyingType == typeof(bool))
						Bool!(reader, parseVal);
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
								Error!("Enum case not found", reader, valType);
						}
						else
						{
							int64 literalData = 0;
							ParseUnderlyingLiteral!(ValueView(val.type, &literalData));
							enumValue |= literalData;
						}
					}
					while (reader.EnumHasMore());

					// Assign value
					switch (valType.Size)
					{
					case 1: *(uint8*)val.dataPtr = *(uint8*)&enumValue;
					case 2: *(uint16*)val.dataPtr = *(uint16*)&enumValue;
					case 4: *(uint32*)val.dataPtr = *(uint32*)&enumValue;
					case 8: *(uint64*)val.dataPtr = *(uint64*)&enumValue;
					default: Debug.FatalError(); // Should be unreachable
					}
				}
				else ParseUnderlyingLiteral!(val);
			}
			else if (valType.IsStruct)
			{
				if (valType == typeof(StringView))
				{
					if (reader.IsNull())
					{
						*(StringView*)val.dataPtr = default;

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

							*(StringView*)val.dataPtr = str;
						}
						else Debug.FatalError("[BON ENV] Register a bonEnvironment.stringViewHandler to deserialize StringViews!");
					}
				}
				else if (valType.IsEnum && valType.IsUnion)
				{
					if (!reader.EnumHasNamed())
						Error!("Expected enum union case name", reader);
					let name = Try!(reader.EnumName());

					ValueView unionPayload = default;
					uint64 unionDiscrIndex = 0;
					ValueView discrVal = default;
					bool foundCase = false, hasCaseData = false;
					for (var enumField in valType.GetFields())
					{
						if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumCase))
						{
							hasCaseData = true;

							if (name == enumField.Name)
							{
								unionPayload = ValueView(enumField.FieldType, val.dataPtr);
								
								foundCase = true;
								break;
							}
							
							unionDiscrIndex++;
						}
						else if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumDiscriminator))
						{
							let discrType = enumField.FieldType;
							Debug.Assert(discrType.IsInteger);
							discrVal = ValueView(discrType, (uint8*)val.dataPtr + enumField.[Friend]mFieldData.mData);
						}
					}

					Debug.Assert(discrVal != default);

					if (!hasCaseData)
						Error!("No reflection data for type", null, valType);
					if (!foundCase)
						Error!("Enum union case not found", reader, valType);

					mixin PutVal<T>() where T : var
					{
						*(T*)discrVal.dataPtr = *(T*)&unionDiscrIndex;
					}

					switch (discrVal.type)
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

					Try!(Struct(reader, unionPayload, env));
				}
				else if (GetCustomHandler(valType, env, let func))
					Try!(func(reader, val, env));
				else Try!(Struct(reader, val, env));
			}
			else if (valType is SizedArrayType)
			{
				if (reader.ArrayHasSizer())
				{
					Try!(reader.ArraySizer<1>(true));

					// Ignore sizer content..
					// we could do some checking, but erroring would be a bit harsh?
				}

				let t = (SizedArrayType)valType;
				Try!(Array(reader, t.UnderlyingType, val.dataPtr, t.ElementCount, env));
			}
			else if (TypeHoldsObject!(valType))
			{
				if (reader.IsNull())
				{
					Try!(NullInstanceRef(reader, val, env));

					Try!(reader.ConsumeEmpty());
				}
				else
				{
					// We may set val's type to polytype for further calls
					var val;

					if (!polyType.IsObject)
					{
						Debug.Assert(valType != polyType);

						let boxType = polyType.BoxedType;
						if (boxType != null)
						{
							// Current reference is of a different type, so clean
							// it up to make our instance below
							if (*(void**)val.dataPtr != null
								&& (*(Object*)val.dataPtr).GetType() != polyType) // Box still returns type of boxed
								Try!(NullInstanceRef(reader, val, env));

							val.type = boxType;

							if (*(void**)val.dataPtr == null)
								Try!(MakeInstanceRef(reader, val, env));

							// Throw together the pointer to the box payload
							// in the corlib approved way. (See Variant.CreateFromBoxed)
							let boxedPtr = (uint8*)*(void**)val.dataPtr + boxType.[Friend]mMemberDataOffset;

							Try!(Value(reader, ValueView(polyType, boxedPtr), env));
						}
						else Error!("Failed to access boxed type", reader, polyType);
					}
					else
					{
						if (polyType != valType)
						{
							// Current reference is of a different type, so clean
							// it up to make our instance below
							if (*(void**)val.dataPtr != null
								&& (*(Object*)val.dataPtr).GetType() != polyType)
								Try!(NullInstanceRef(reader, val, env));

							val.type = polyType;
						}
						else Debug.Assert(!valType.IsInterface);

						if (*(void**)val.dataPtr == null
							&& !polyType.IsArray) // Arrays handle it differently
							Try!(MakeInstanceRef(reader, val, env));

						if (polyType.IsArray) ARRAY:
						{
							Debug.Assert(polyType != typeof(Array) && polyType is ArrayType);

							let t = polyType as ArrayType;

							int64 fullCount = 0;
							int64[] counts = null;
							switch (t.UnspecializedType)
							{
							case typeof(Array1<>):
								if (reader.ArrayHasSizer())
								{
									let sizer = Try!(reader.ArraySizer<1>(false));
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
								let sizer = Try!(reader.ArraySizer<2>(false));
								counts = scope:ARRAY .[2];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));

								fullCount = counts[0] * counts[1];

							case typeof(Array3<>):
								let sizer = Try!(reader.ArraySizer<3>(false));
								counts = scope:ARRAY .[3];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));
								counts[2] = Try!(ParseInt<int_arsize>(reader, sizer[2]));

								fullCount = counts[0] * counts[1] * counts[2];

							case typeof(Array4<>):
								let sizer = Try!(reader.ArraySizer<4>(false));
								counts = scope:ARRAY .[4];
								counts[0] = Try!(ParseInt<int_arsize>(reader, sizer[0]));
								counts[1] = Try!(ParseInt<int_arsize>(reader, sizer[1]));
								counts[2] = Try!(ParseInt<int_arsize>(reader, sizer[2]));
								counts[3] = Try!(ParseInt<int_arsize>(reader, sizer[3]));

								fullCount = counts[0] * counts[1] * counts[2] * counts[3];

							default:
								Debug.FatalError();
							}

							// Old array if count doesn't match!
							if (*(void**)val.dataPtr != null)
							{
								let currCount = GetValField!<int_arsize>(val, "mLength");
								if (fullCount != currCount)
									Try!(NullInstanceRef(reader, val, env));
							}

							if (*(void**)val.dataPtr == null)
							{
								// We're screwed on big collections, but who uses that...? hah
								Try!(MakeArrayInstanceRef(val, (int32)fullCount));
							}
							Debug.Assert(GetValField!<int_arsize>(val, "mLength") == fullCount);

							let arrType = t.GetGenericArg(0); // T
							let classData = *(uint8**)val.dataPtr;

							void* arrPtr = null;
							if (t.GetField("mFirstElement") case .Ok(let field))
								arrPtr = classData + field.MemberOffset; // T*
							else Error!("No reflection data for array type. For example: force with [BonTarget] extension Array1<T> {} or through build settings", null, t);

							switch (t.UnspecializedType)
							{
							case typeof(Array4<>):
								SetValField!(val, "mLength3", (int_arsize)counts[3]);
								fallthrough;
							case typeof(Array3<>):
								SetValField!(val, "mLength2", (int_arsize)counts[2]);
								fallthrough;
							case typeof(Array2<>):
								SetValField!(val, "mLength1", (int_arsize)counts[1]);

								Try!(MultiDimensionalArray(reader, arrType, arrPtr, env, params counts));

							case typeof(Array1<>):
								Try!(Array(reader, arrType, arrPtr, fullCount, env));

							default:
								Debug.FatalError();
							}
						}
						else if (GetCustomHandler(polyType, env, let func))
							Try!(func(reader, val, env));
						else Try!(Class(reader, val, env));
					}
				}
			}
			else if (valType.IsPointer)
			{
				Error!("Cannot handle pointer values", reader, valType);
			}
			else
			{
				Debug.FatalError();
				Error!("Unhandled. Please report this", reader, valType);
			}

			return .Ok;
		}

		static bool GetCustomHandler(Type type, BonEnvironment env, out HandleDeserializeFunc func)
		{
			if (env.typeHandlers.TryGetValue(type, let val) && val.deserialize != null)
			{
				func = val.deserialize;
				return true;
			}
			else if (type is SpecializedGenericType && env.typeHandlers.TryGetValue(((SpecializedGenericType)type).UnspecializedType, let gVal)
				&& gVal.deserialize != null)
			{
				func = gVal.deserialize;
				return true;
			}
			func = null;
			return false;
		}

		public static Result<void> Class(BonReader reader, ValueView val, BonEnvironment env)
		{
			let classType = val.type;
			Debug.Assert(classType.IsObject);

			Try!(Struct(reader, ValueView(classType, *(void**)val.dataPtr), env));

			return .Ok;
		}

		public static Result<void> Struct(BonReader reader, ValueView val, BonEnvironment env)
		{
			let structType = val.type;
			Try!(reader.ObjectBlock());

			List<FieldInfo> fields = scope .(structType.FieldCount);
			for (let f in structType.GetFields(.Instance))
				fields.Add(f);

			if (fields.Count == 0 && reader.ObjectHasMore())
				Error!("No reflection data for type", null, structType);

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
					Error!("Failed to find field", reader, structType);

				if (!env.deserializeFlags.HasFlag(.AccessNonPublic) // we don't allow non-public
					&& !(fieldInfo.[Friend]mFieldData.mFlags.HasFlag(.Public) || fieldInfo.GetCustomAttribute<BonIncludeAttribute>() case .Ok) // field is not accessible
					|| fieldInfo.GetCustomAttribute<BonIgnoreAttribute>() case .Ok) // or field is ignored
					Error!("Field access not allowed", reader, structType);

				Try!(Value(reader, ValueView(fieldInfo.FieldType, ((uint8*)val.dataPtr) + fieldInfo.MemberOffset), env));

				if (reader.ObjectHasMore())
					Try!(reader.EntryEnd());
			}

			if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
			{
				for (let f in fields)
					Try!(MakeDefault(reader, ValueView(f.FieldType, ((uint8*)val.dataPtr) + f.MemberOffset), env));
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
					var arrVal = ValueView(arrType, ptr);

					if (reader.IsIrrelevantEntry())
					{
						// Null unless we leave these alone!
						if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
							Try!(MakeDefault(reader, arrVal, env));

						Try!(reader.ConsumeEmpty());
					}
					else Try!(Value(reader, arrVal, env));

					if (reader.ArrayHasMore())
						Try!(reader.EntryEnd());

					ptr += arrType.Stride;
				}

				if (!env.deserializeFlags.HasFlag(.IgnoreUnmentionedValues))
				{
					if (arrType.IsValueType)
						Internal.MemSet(ptr, 0, arrType.Stride * ((int)count - i), arrType.Align); // MakeDefault would just do the same here
					else
					{
						// Default unaffected entries (since they aren't serialized)
						for (let j < count - i)
						{
							Try!(MakeDefault(reader, ValueView(arrType, ptr), env));

							ptr += arrType.Stride;
						}
					}
				}
			}
			if (reader.ArrayHasMore())
				Error!("Array cannot fit element", reader);

			return reader.ArrayBlockEnd();
		}

		public static Result<void> MultiDimensionalArray(BonReader reader, Type arrType, void* arrPtr, BonEnvironment env, params int64[] counts)
		{
			Debug.Assert(counts.Count > 1); // Must be multi-dimensional!

			let count = counts[0];
			int stride = (.)counts[1];
			if (counts.Count > 2)
				for (let i < counts.Count - 2)
					stride *= (.)counts[i + 2];
			stride *= arrType.Stride;

			mixin DefaultArray(void* ptr)
			{
				let inner = counts.Count - 1;
				if (inner > 1)
				{
					int64[] innerCounts = scope .[inner];
					for (let j < inner)
						innerCounts[j] = counts[j + 1];

					Try!(DefaultMultiDimensionalArray(reader, arrType, ptr, env, params innerCounts));
				}
				else Try!(DefaultArray(reader, arrType, ptr, counts[1], env));
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
								Internal.MemSet(ptr, 0, stride, arrType.Align); // MakeDefault would just do the same here
							else DefaultArray!(ptr);
						}

						Try!(reader.ConsumeEmpty());
					}
					else
					{
						let inner = counts.Count - 1;
						if (inner > 1)
						{
							int64[] innerCounts = scope .[inner];
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
						Internal.MemSet(ptr, 0, stride * (.)(count - i), arrType.Align); // MakeDefault would just do the same here
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
				Error!("Array cannot fit element", reader);

			return reader.ArrayBlockEnd();
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
				else Error!("Failed to parse integer", reader,  typeof(T));

				digits++;

				if (result < prevRes)
					Error!("Integer is out of range", reader, typeof(T));
				prevRes = result;
			}

			// Check overflow
			if (isNegative)
			{
				if (result > int64.MaxValue)
					Error!("Integer is out of range", reader, typeof(T));
				let num = -(*(int64*)&result);
				if (num < (int64)T.MinValue || num > (int64)T.MaxValue)
					Error!("Integer is out of range", reader, typeof(T));
				else return .Ok((T)num);
			}
			else
			{
				let num = result;
				if (result > (uint64)T.MaxValue)
					Error!("Integer is out of range", reader, typeof(T));
				else return .Ok((T)num);
			}
		}

		static mixin ParseThing<T>(BonReader reader, StringView num) where T : var
		{
			T thing = default;
			if (!(T.Parse(.(&num[0], num.Length)) case .Ok(out thing)))
				Error!("Failed to parse", reader, typeof(T));
			thing
		}

		static mixin Integer(Type type, BonReader reader, ValueView val)
		{
			let num = Try!(reader.Integer());

			switch (type)
			{
			case typeof(int8): *(int8*)val.dataPtr = Try!(ParseInt<int8>(reader, num));
			case typeof(int16): *(int16*)val.dataPtr = Try!(ParseInt<int16>(reader, num));
			case typeof(int32): *(int32*)val.dataPtr = Try!(ParseInt<int32>(reader, num));
			case typeof(int64): *(int64*)val.dataPtr = Try!(ParseInt<int64>(reader, num));
			case typeof(int): *(int*)val.dataPtr = Try!(ParseInt<int>(reader, num));

			case typeof(uint8): *(uint8*)val.dataPtr = Try!(ParseInt<uint8>(reader, num));
			case typeof(uint16): *(uint16*)val.dataPtr = Try!(ParseInt<uint16>(reader, num));
			case typeof(uint32): *(uint32*)val.dataPtr = Try!(ParseInt<uint32>(reader, num));
			case typeof(uint64): *(uint64*)val.dataPtr = Try!(ParseInt<uint64>(reader, num));
			case typeof(uint): *(uint*)val.dataPtr = Try!(ParseInt<uint>(reader, num));
			}
		}

		static mixin Float(Type type, BonReader reader, ValueView val)
		{
			let num = Try!(reader.Floating());

			switch (type)
			{
			case typeof(float): *(float*)val.dataPtr = ParseThing!<float>(reader, num);
			case typeof(double): *(double*)val.dataPtr = ParseThing!<double>(reader, num);
			}
		}

		static mixin DoChar<T, TI>(BonReader reader, ValueView val, char32 char) where T : var where TI : var
		{
			if ((uint)char > TI.MaxValue)
				Error!("Char is out of range", reader, typeof(T));

			*(T*)val.dataPtr = *(T*)&char;
		}

		static mixin Char(Type type, BonReader reader, ValueView val)
		{
			var char = Try!(reader.Char());

			switch (type)
			{
			case typeof(char8): DoChar!<char8, uint8>(reader, val, char);
			case typeof(char16): DoChar!<char16, uint16>(reader, val, char);
			case typeof(char32): DoChar!<char32, uint32>(reader, val, char);
			}
		}

		static mixin Bool(BonReader reader, ValueView val)
		{
			let b = Try!(reader.Bool());

			*(bool*)val.dataPtr = b;
		}
	}
}