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
	struct DeserializeValueState
	{
		public bool arrayKeepUnlessSet, keepUnlessSet;
	}

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
#if TEST || BON_CONSOLE_PRINT
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

		static mixin GetStateFromValueFieldForDefault(FieldInfo fieldInfo)
		{
			var state = DeserializeValueState();
			if (fieldInfo.HasCustomAttribute<BonArrayKeepUnlessSetAttribute>())
				state.arrayKeepUnlessSet = true;
			state
		}

		public static Result<void> MakeDefault(BonReader reader, ValueView val, BonEnvironment env, bool isExplicit, DeserializeValueState state = default)
		{
			if (ValueDataIsZero!(val))
				return .Ok;

			let canQuickDefault = Try!(CheckCanDefault(reader, val, env, isExplicit, true, state));

			MakeDefaultUnchecked(reader, val, env, isExplicit, canQuickDefault, state);

			return .Ok;
		}

		/// CheckCanDefault beforehand!
		public static void MakeDefaultUnchecked(BonReader reader, ValueView val, BonEnvironment env, bool isExplicit, bool canQuickDefault, DeserializeValueState state = default)
		{
			if (canQuickDefault)
			{
				let ptr = val.dataPtr;
				let size = val.type.Size;

				bool memset = true;
				let align = val.type.Align;

				if (align == size)
				{
					memset = false;
					switch (size)
					{
					case 0:
					case 1: *(uint8*)ptr = 0;
					case 2: *(uint16*)ptr = 0;
					case 4: *(uint32*)ptr = 0;
					case 8: *(uint64*)ptr = 0;
					default:
						memset = true;
					}
				}
				if (memset)
					Internal.MemSet(ptr, 0, size, align);
			}
			else MakeDefaultComplicated(reader, val, env, isExplicit, state);
		}

		static void MakeDefaultComplicated(BonReader reader, ValueView val, BonEnvironment env, bool isExplicit, DeserializeValueState state = default)
		{
			// We *can* null everything we need to, but need to ignore some fields!
			// So we need to be careful and slowly walk everything...

			let valType = val.type;
			if (valType.IsStruct)
			{
				if (valType.IsEnum && valType.IsUnion)
				{
					let payloadVal = Serialize.GetPayloadValueFromEnumUnion(val, ?, let caseIndex);
					if (payloadVal != default)
						MakeDefaultStructComplicated(reader, payloadVal, isExplicit, env);
					else Debug.FatalError(); // Should have caught this
				}
				else MakeDefaultStructComplicated(reader, val, isExplicit, env);
			}
			else if (valType.IsSizedArray)
			{
				if (state.arrayKeepUnlessSet)
					return;

				let t = (SizedArrayType)valType;
				let arrType = t.UnderlyingType;
				let count = t.ElementCount;
				var ptr = (uint8*)val.dataPtr;

				if (IsTypeAlwaysDefaultable!(arrType))
					Internal.MemSet(ptr, 0, count * arrType.Stride, arrType.Align);
				else
				{
					for (let j < count)
					{
						let fieldVal = ValueView(arrType, ptr);
						if (ValueDataIsZero!(fieldVal))
							continue;

						MakeDefaultComplicated(reader, fieldVal, env, isExplicit);

						ptr += arrType.Stride;
					}
				}
			}
			else Internal.MemSet(val.dataPtr, 0, valType.Size, valType.Align);
		}

		static void MakeDefaultStructComplicated(BonReader reader, ValueView val, bool isExplicit, BonEnvironment env)
		{
			var structIsKeepUnlessSet = false;
			if (!isExplicit)
				structIsKeepUnlessSet = val.type.HasCustomAttribute<BonKeepMembersUnlessSetAttribute>();

			for (let f in val.type.GetFields(.Instance))
			{
				let fieldVal = ValueView(f.FieldType, (uint8*)val.dataPtr + f.MemberOffset);
				if (ValueDataIsZero!(fieldVal) || ShouldIgnoreField!(f, env)
					|| !isExplicit && (structIsKeepUnlessSet || f.HasCustomAttribute<BonKeepUnlessSetAttribute>()))
					continue;

				MakeDefaultComplicated(reader, fieldVal, env, isExplicit,
					!isExplicit ? GetStateFromValueFieldForDefault!(f) : default);
			}
		}

		public static Result<void> DefaultArray(BonReader reader, Type arrType, void* arrPtr, int64 count, BonEnvironment env, bool isExplicit)
		{
			var ptr = (uint8*)arrPtr;
			for (let j < count)
			{
				Try!(MakeDefault(reader, ValueView(arrType, ptr), env, isExplicit));

				ptr += arrType.Stride;
			}
			return .Ok;
		}

		public static Result<void> DefaultMultiDimensionalArray(BonReader reader, Type arrType, void* arrPtr, BonEnvironment env, bool isExplicit, params int64[] counts)
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

						Try!(DefaultMultiDimensionalArray(reader, arrType, ptr, env, isExplicit, params innerCounts));
					}
					else Try!(DefaultArray(reader, arrType, ptr, counts[1], env, isExplicit));

					ptr += stride;
				}
			}
			return .Ok;
		}

		public static Result<bool> CheckCanDefault(BonReader reader, ValueView val, BonEnvironment env, bool isExplicit, bool zeroCheckDone = false, DeserializeValueState state = default)
		{
			if (!zeroCheckDone && ValueDataIsZero!(val))
				return .Ok(true);

			let valType = val.type;
			if (valType.IsStruct)
			{
				if (valType.IsEnum && valType.IsUnion)
				{
					let payloadVal = Serialize.GetPayloadValueFromEnumUnion(val, ?, let caseIndex);
					if (payloadVal != default)
					{
						if (!Try!(CheckCanDefaultStruct(reader, payloadVal, env, isExplicit)))
						{
							// Something in there doesn't wants to be ignored please...

							if (caseIndex != 0)
								Error!("Cannot default field nested in non-default enum union case", reader, valType);

							return .Ok(false);
						}
					}
					else
					{
						if (valType.FieldCount <= 2) // Always has two fields
							Error!("Cannot default enum union with no reflection data", reader, valType);
						else Error!("Cannot default enum union with corrupted value", reader, valType);
					}
				}
				else return CheckCanDefaultStruct(reader, val, env, isExplicit);
			}
			else if (valType.IsSizedArray)
			{
				// This array is clearly not set at all, so just leave everything alone.
				// To do this, we will need to take the complicated path though...
				if (state.arrayKeepUnlessSet)
					return .Ok(false);

				let t = (SizedArrayType)valType;
				let arrType = t.UnderlyingType;
				let count = t.ElementCount;
				var ptr = (uint8*)val.dataPtr;

				bool canQuickDefault = true;
				for (let j < count)
				{
					canQuickDefault &= Try!(CheckCanDefault(reader, ValueView(arrType, ptr), env, isExplicit));

					ptr += arrType.Stride;
				}
				return .Ok(canQuickDefault);
			}
			else if (TypeHoldsObject!(valType))
				Error!("Cannot null reference to default", reader, valType);
			else if (valType.IsPointer)
				Error!("Cannot handle pointer values to default", reader, valType);

			return .Ok(true);
		}

		static Result<bool> CheckCanDefaultStruct(BonReader reader, ValueView val, BonEnvironment env, bool isExplicit)
		{
			if (val.type.FieldCount == 0)
				Error!("Cannot default struct with no reflection data", reader, val.type);

			bool canQuickDefault = true;
			bool structIsKeepUnlessSet = false;
			if (!isExplicit)
				structIsKeepUnlessSet = val.type.HasCustomAttribute<BonKeepMembersUnlessSetAttribute>();

			for (let f in val.type.GetFields(.Instance))
			{
				let fieldType = f.FieldType;
				let fieldVal = ValueView(fieldType, (uint8*)val.dataPtr + f.MemberOffset);

				if (ValueDataIsZero!(fieldVal))
					continue;

				if (ShouldIgnoreField!(f, env)
					|| !isExplicit && (structIsKeepUnlessSet || f.HasCustomAttribute<BonKeepUnlessSetAttribute>()))
				{
					canQuickDefault = false;
					continue;
				}

				canQuickDefault &= Try!(CheckCanDefault(reader, fieldVal, env, isExplicit, true,
					!isExplicit ? GetStateFromValueFieldForDefault!(f) : default));
			}

			return .Ok(canQuickDefault);
		}

		[Inline]
		public static Result<void> NullInstanceRef(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (*(void**)val.dataPtr != null)
				Error!("Cannot null reference", reader, val.type);

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

			Try!(Value(reader, val, env));

			return End(reader);
		}

		public static Result<void> Value(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state = default)
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
					else if (typeName != (StringView)valType.GetFullName(.. scope .(256))) // It's the base type itself, and we got that!
						Error!("Specified type not found in bonEnvironment.polyTypes", reader, valType);
				}
				else Error!("Type markers are only valid on reference types and interfaces", reader, valType);
			}

			if (reader.IsDefault())
			{
				Try!(MakeDefault(reader, val, env, true, state));
				Try!(reader.ConsumeEmpty());
			}
			else if (reader.IsIrrelevantEntry())
			{
				if (!state.keepUnlessSet)
					Try!(MakeDefault(reader, val, env, false, state));

				Try!(reader.ConsumeEmpty());
			}
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
							if (str.Ptr == parsedStr.Ptr)
								Error!("[BON ENV] Seriously? bonEnvironment.stringViewHandler returned passed in view but should manage the string's memory!", reader);
							if (str != parsedStr)
								Error!("[BON ENV] bonEnvironment.stringViewHandler returned altered string!", reader);

							*(StringView*)val.dataPtr = str;
						}
						else Error!("[BON ENV] Register a bonEnvironment.stringViewHandler to deserialize StringViews!", reader);
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

					let payloadVal = Serialize.GetPayloadValueFromEnumUnion(val, ?, let currentDiscrIndex);
					if (payloadVal != default)
					{
						// When we're changing enum union case we need to erase the previous value since fields shift,
						// otherwise weird stuff might happen

						if (currentDiscrIndex != unionDiscrIndex)
							if (MakeDefault(reader, val, env, true) case .Err)
								Error!("Cannot default current enum union case to deserialize another (linked with previous error)", reader, valType);
					}
					else Error!("Cannot deserialize into enum union with corrupted value", reader, valType);

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
					Try!(func(reader, val, env, state));
				else Try!(Struct(reader, val, env));
			}
			else if (valType.IsSizedArray)
			{
				if (reader.ArrayHasSizer())
				{
					Try!(reader.ArraySizer<1>(true));

					// Ignore sizer content..
					// we could do some checking, but erroring would be a bit harsh?
				}

				let t = (SizedArrayType)valType;
				Try!(Array(reader, t.UnderlyingType, val.dataPtr, t.ElementCount, env, state.arrayKeepUnlessSet));
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

								Try!(MultiDimensionalArray(reader, arrType, arrPtr, env, state.arrayKeepUnlessSet, params counts));

							case typeof(Array1<>):
								Try!(Array(reader, arrType, arrPtr, fullCount, env, state.arrayKeepUnlessSet));

							default:
								Debug.FatalError();
							}
						}
						else if (GetCustomHandler(polyType, env, let func))
							Try!(func(reader, val, env, state));
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

		static mixin ShouldIgnoreField(FieldInfo f, BonEnvironment env)
		{
			!(f.[Friend]mFieldData.mFlags.HasFlag(.Public) || f.HasCustomAttribute<BonIncludeAttribute>()) // field is not accessible
			|| f.HasCustomAttribute<BonIgnoreAttribute>()
		}

		static mixin GetStateFromValueField(FieldInfo fieldInfo)
		{
			DeserializeValueState state = default;
			if (fieldInfo.HasCustomAttribute<BonArrayKeepUnlessSetAttribute>())
				state.arrayKeepUnlessSet = true;
			if (fieldInfo.HasCustomAttribute<BonKeepUnlessSetAttribute>())
				state.keepUnlessSet = true;
			state
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

			let keepMembersUnlessSet = structType.HasCustomAttribute<BonKeepMembersUnlessSetAttribute>();
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

				if (ShouldIgnoreField!(fieldInfo, env))
					Error!("Field access not allowed", reader, structType);

				var state = GetStateFromValueField!(fieldInfo);
				if (keepMembersUnlessSet)
					state.keepUnlessSet = true;

				Try!(Value(reader, ValueView(fieldInfo.FieldType, ((uint8*)val.dataPtr) + fieldInfo.MemberOffset), env, state));

				if (reader.ObjectHasMore())
					Try!(reader.EntryEnd());
			}

			if (!keepMembersUnlessSet)
			{
				for (let f in fields)
				{
					if (ShouldIgnoreField!(f, env) || f.HasCustomAttribute<BonKeepUnlessSetAttribute>())
						continue;

					let state = GetStateFromValueField!(f);
					Try!(MakeDefault(reader, ValueView(f.FieldType, ((uint8*)val.dataPtr) + f.MemberOffset), env, false, state));
				}
			}

			return reader.ObjectBlockEnd();
		}

		static mixin IsTypeAlwaysDefaultable(Type type)
		{
			type.IsPrimitive || type.IsTypedPrimitive || type.IsEnum
		}

		public static Result<void> Array(BonReader reader, Type arrType, void* arrPtr, int64 count, BonEnvironment env, bool keepValuesUnlessSet = false)
		{
			Try!(reader.ArrayBlock());

			if (count > 0)
			{
				DeserializeValueState state = .{
					keepUnlessSet = keepValuesUnlessSet
				};

				var ptr = (uint8*)arrPtr;
				var i = 0;
				for (; i < count && reader.ArrayHasMore(); i++)
				{
					Try!(Value(reader, ValueView(arrType, ptr), env, state));

					if (reader.ArrayHasMore())
						Try!(reader.EntryEnd());

					ptr += arrType.Stride;
				}

				if (!keepValuesUnlessSet)
				{
					if (IsTypeAlwaysDefaultable!(arrType))
						Internal.MemSet(ptr, 0, arrType.Stride * ((int)count - i), arrType.Align); // MakeDefault would just do the same here
					else
					{
						// Default unaffected entries (since they aren't serialized)
						let len = count - i;
						for (let j < len)
						{
							Try!(MakeDefault(reader, ValueView(arrType, ptr), env, false));

							ptr += arrType.Stride;
						}
					}
				}
			}
			if (reader.ArrayHasMore())
				Error!("Array cannot fit element", reader);

			return reader.ArrayBlockEnd();
		}

		public static Result<void> MultiDimensionalArray(BonReader reader, Type arrType, void* arrPtr, BonEnvironment env, bool keepValuesUnlessSet = false, params int64[] counts)
		{
			Debug.Assert(counts.Count > 1); // Must be multi-dimensional!

			let count = counts[0];
			int stride = (.)counts[1];
			if (counts.Count > 2)
				for (let i < counts.Count - 2)
					stride *= (.)counts[i + 2];
			stride *= arrType.Stride;

			mixin DefaultArray(void* ptr, bool isExplicit)
			{
				let inner = counts.Count - 1;
				if (inner > 1)
				{
					int64[] innerCounts = scope .[inner];
					for (let j < inner)
						innerCounts[j] = counts[j + 1];

					Try!(DefaultMultiDimensionalArray(reader, arrType, ptr, env, isExplicit, params innerCounts));
				}
				else Try!(DefaultArray(reader, arrType, ptr, counts[1], env, isExplicit));
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
						if (!keepValuesUnlessSet)
						{
							if (IsTypeAlwaysDefaultable!(arrType))
								Internal.MemSet(ptr, 0, stride, arrType.Align); // MakeDefault would just do the same here
							else DefaultArray!(ptr, isDefault);
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

							Try!(MultiDimensionalArray(reader, arrType, ptr, env, keepValuesUnlessSet, params innerCounts));
						}
						else Try!(Array(reader, arrType, ptr, counts[1], env, keepValuesUnlessSet));
					}

					if (reader.ArrayHasMore())
						Try!(reader.EntryEnd());

					ptr += stride;
				}

				if (!keepValuesUnlessSet)
				{
					if (IsTypeAlwaysDefaultable!(arrType))
						Internal.MemSet(ptr, 0, stride * (.)(count - i), arrType.Align); // MakeDefault would just do the same here
					else
					{
						// Default unaffected entries (since they aren't serialized)
						for (let j < count - i)
						{
							DefaultArray!(ptr, false);

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
				Debug.FatalError();

			uint64 prevRes = 0;
			uint64 result = 0;
			bool isNegative = false;
			bool allowBaseSpec = false;
			uint64 radix = 10;
			int digits = 0;

			var i = 0;
			let first = val[0];
			if (first == '-')
			{
				if (typeof(T).IsSigned)
					isNegative = true;
				else Error!("Integer is unsigned", reader,  typeof(T));

				i++;
			}
			else if (first == '+')
				i++;

			for (; i < len; i++)
			{
				let c = val[[Unchecked]i];

				if ((c == '0') || (c == '1'))
				{
					if (digits == 0 && c == '0')
					{
						if (allowBaseSpec)
						{
							// We were already here... there are at least two leading zeros, don't allow base spec anymore!
							// This will cause us to process the redundant zeros, but whatever. No difference
							digits++;
						}

						allowBaseSpec = true;
						continue; // Don't count leading 0s as digit
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
				else if (c == '\'')
					continue;
				else Error!("Failed to parse integer", reader,  typeof(T));

				digits++;

				if (result < prevRes)
					Error!("Value is out of range for integer", reader, typeof(T));
				prevRes = result;
			}

			// Check overflow
			if (isNegative)
			{
				if (result > int64.MaxValue)
					Error!("Value is out of range for integer", reader, typeof(T));
				let num = -(*(int64*)&result);
				if (num < (int64)T.MinValue || num > (int64)T.MaxValue)
					Error!("Value is out of range for integer", reader, typeof(T));
				else return .Ok((T)num);
			}
			else
			{
				let num = result;
				if (result > (uint64)T.MaxValue)
					Error!("Value is out of range for integer", reader, typeof(T));
				else return .Ok((T)num);
			}
		}

		public static Result<T> ParseFloat<T>(BonReader reader, StringView val) where T : IFloating, var
		{
			if (val.IsEmpty)
				Debug.FatalError();

			bool isNeg = val[0] == '-';
			bool isPos = val[0] == '+';

			var val;
			if (isNeg || isPos)
				val.RemoveFromStart(1);

			if (val.Equals("Infinity", true))
			{
				if (isNeg)
					return T.NegativeInfinity;
				else return T.PositiveInfinity;
			}
			else if (@val.Equals("NaN", true))
				return T.NaN;
			
			T result = 0;
			T decimalMultiplier = 0;
			bool decimalStarted = false;

			let len = val.Length;
			for (var i = 0; i < len; i++)
			{
				char8 c = val[[Unchecked]i];

				// Exponent prefix used in scientific notation. E.g. 1.2E5
				if (c == 'e' || c == 'E')
				{
					if (!decimalStarted)
						Error!("Invalid notation", reader, typeof(T));
					else if(i == len - 1)
						Error!("Expected exponent", reader, typeof(T));
					if (ParseInt<int32>(reader, val.Substring(i + 1)) case .Ok(let exponent))
						result *= Math.Pow(10, (T)exponent);
					else Error!("Failed to parse exponent (linked with previous error)", reader, typeof(T));

					break;
				}

				decimalStarted = true;

				if (c == '.')
				{
					if (decimalMultiplier != 0)
						Error!("More than one decimal separator", reader, typeof(T));
					decimalMultiplier = (T)0.1;

					continue;
				}
				if (decimalMultiplier != 0)
				{
					if ((c >= '0') && (c <= '9'))
					{
						result += (.)(c - '0') * decimalMultiplier;
						decimalMultiplier *= (T)0.1;
					}
					else
						Error!("Invalid notation", reader, typeof(T));

					continue;
				}

				if ((c >= '0') && (c <= '9'))
				{
					result *= 10;
					result += (.)(c - '0');
				}
				else
					Error!("Invalid notation", reader, typeof(T));
			}
			return isNeg ? (result * -1) : result;
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
			case typeof(float): *(float*)val.dataPtr = Try!(ParseFloat<float>(reader, num));
			case typeof(double): *(double*)val.dataPtr = Try!(ParseFloat<double>(reader, num));
			}
		}

		static mixin DoChar<T, TI>(BonReader reader, ValueView val, char32 char) where T : var where TI : var
		{
			if ((uint64)char > TI.MaxValue)
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