using System;
using System.Diagnostics;
using System.Reflection;

namespace Bon.Integrated
{
	static class Serialize
	{
		static mixin DoInclude(ref Variant val, BonSerializeFlags flags)
		{
			(flags.HasFlag(.IncludeDefault) || !VariantDataIsZero!(val))
		}

		static mixin DoTypeOneLine(Type type, BonSerializeFlags flags)
		{
			(type.IsPrimitive || (type.IsTypedPrimitive && (!flags.HasFlag(.Verbose) || !type.IsEnum)))
		}

		public static void Thing(BonWriter writer, ref Variant val, BonEnvironment env)
		{
			writer.Start();
			if (DoInclude!(ref val, env.serializeFlags))
				Value(writer, ref val, env);
			
			if (writer.outStr.Length == 0)
			{
				// We never explicitly place default automatically to enable DeserializeFlags.IgnoreUnmentionedValues
				// we still need this in order to not shift the file-level "array"
				Irrelevant(writer);
			}

			writer.End();
		}

		public static void Value(BonWriter writer, ref Variant val, BonEnvironment env, bool doOneLine = false)
		{
			let valType = val.VariantType;

			// Make sure that doOneLineVal is only passed when valid
			Debug.Assert(!doOneLine || DoTypeOneLine!(valType, env.serializeFlags));

			writer.EntryStart(doOneLine);

			if (valType.IsPrimitive)
			{
				if (valType.IsInteger)
					Integer(valType, writer, ref val);
				else if (valType.IsFloatingPoint)
					Float(valType, writer, ref val);
				else if (valType.IsChar)
					Char(valType, writer, ref val);
				else if (valType == typeof(bool))
					Bool(writer, ref val, env.serializeFlags);
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{
				// Is used to change what will be printed if the enum has a remainder
				// to be printed as a literal
				int64 enumRemainderVal = 0;
				var printVal = val;

				bool doPrintLiteral = true;
				if (valType.IsEnum && env.serializeFlags.HasFlag(.Verbose))
				{
					doPrintLiteral = false;

					int64 valueData = 0;
					Span<uint8>((uint8*)val.DataPtr, valType.Size).CopyTo(Span<uint8>((uint8*)&valueData, valType.Size));

					bool found = false;
					for (var field in valType.GetFields())
					{
						if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase) &&
							*(int64*)&field.[Friend]mFieldData.[Friend]mData == valueData)
						{
							writer.Enum(field.Name);
							found = true;
							break;
						}
					}

					if (!found)
					{
						// There is no exact named value here, but maybe multiple!

						// We only try once, but that's better than none. If you were
						// to have this enum { A = 0b0011, B = 0b0111, C = 0b1100 }
						// and run this on 0b1111, this algorithm would fail to
						// identify .A | .C, but rather .B | 0b1000 because it takes
						// the largest match first and never looks back if it doesn't
						// work out. The easiest way to make something more complicated
						// work would probably be recursion... maybe in the future
						enumRemainderVal = valueData;
						String bestValName = scope .();
						bool foundAny = false;
						while (enumRemainderVal != 0)
						{
							// Go through all values and find best match in therms of bits
							int64 bestVal = 0;
							var bestValBits = 0;
							for (var field in valType.GetFields())
							{
								if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase))
								{
									let fieldVal = *(int64*)&field.[Friend]mFieldData.[Friend]mData;

									if (fieldVal == 0 || (fieldVal & ~enumRemainderVal) != 0)
										continue; // fieldVal contains bits that valueLeft doesn't have

									var bits = 0;
									for (let i < sizeof(int64) * 8)
										if (((fieldVal >> i) & 0b1) != 0)
											bits++;

									if (bits > bestValBits)
									{
										bestVal = fieldVal;
										bestValName.Set(field.Name);
										bestValBits = bits;
									}
								}
							}

							if (bestValBits > 0)
							{
								enumRemainderVal &= ~bestVal; // Remove all bits it shares with this
								writer.Enum(bestValName);
								foundAny = true;
							}
							else
							{
								if (foundAny)
									writer.EnumAdd();

								// Print remainder literal
								doPrintLiteral = true;
								printVal = Variant.CreateReference(val.VariantType, &enumRemainderVal);

								break;
							}

							if (enumRemainderVal == 0)
								break;
						}
					}
				}

				// Print on non-enum types, and if the enum need to append the leftover value as literal
				// or in any case if we're not printing verbose
				if (doPrintLiteral)
				{
					if (valType.UnderlyingType.IsInteger)
						Integer(valType.UnderlyingType, writer, ref printVal);
					else if (valType.UnderlyingType.IsFloatingPoint)
						Float(valType.UnderlyingType, writer, ref printVal);
					else if (valType.UnderlyingType.IsChar)
						Char(valType.UnderlyingType, writer, ref printVal);
					else if (valType.UnderlyingType == typeof(bool))
						Bool(writer, ref printVal, env.serializeFlags);
					else Debug.FatalError(); // Should be unreachable
				}
			}
			else if (valType.IsStruct)
			{
				if (valType == typeof(StringView))
				{
					let view = val.Get<StringView>();

					if (view.Ptr == null)
						writer.Null();
					else writer.String(view);
				}
				else if (valType.IsEnum && valType.IsUnion)
				{
					// Enum union in memory:
					// {<payload>|<discriminator>}

					bool didWrite = false;
					bool foundCase = false;
					uint64 unionCaseIndex = 0;
					uint64 currCaseIndex = 0;
					for (var enumField in valType.GetFields())
					{
						if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumDiscriminator))
						{
							let discrType = enumField.FieldType;
							var discrVal = Variant.CreateReference(discrType, (uint8*)val.DataPtr + enumField.[Friend]mFieldData.mData);
							Debug.Assert(discrType.IsInteger);

							mixin GetVal<T>() where T : var
							{
								T thing = *(T*)discrVal.DataPtr;
								unionCaseIndex = (uint64)thing;
							}

							switch (discrType)
							{
							case typeof(int8): GetVal!<int8>();
							case typeof(int16): GetVal!<int16>();
							case typeof(int32): GetVal!<int32>();
							case typeof(int64): GetVal!<int64>();
							case typeof(int): GetVal!<int>();

							case typeof(uint8): GetVal!<uint8>();
							case typeof(uint16): GetVal!<uint16>();
							case typeof(uint32): GetVal!<uint32>();
							case typeof(uint64): GetVal!<uint64>();
							case typeof(uint): GetVal!<uint>();

							default: Debug.FatalError(); // Should be unreachable
							}

							foundCase = true;
						}
						else if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumCase)) // Filter through unioncaseIndex
						{
							Debug.Assert(foundCase);

							// Skip enum cases until we get to the selected one
							if (currCaseIndex != unionCaseIndex)
							{
								currCaseIndex++;
								continue;
							}

							var unionPayload = Variant.CreateReference(enumField.FieldType, val.DataPtr);

							// Do serialize of discriminator and payload
							writer.Enum(enumField.Name);
							Struct(writer, ref unionPayload, env);

							didWrite = true;
							break;
						}
					}

					Debug.Assert(didWrite);
				}
				else Struct(writer, ref val, env);
			}
			else if (valType is SizedArrayType)
			{
				let t = (SizedArrayType)valType;
				let count = t.ElementCount;

				// Since this is a fixed-size array, this info is not necessary to
				// deserialize in any case. But it's nice for manual editing to know how
				// much the array can hold
				if (env.serializeFlags.HasFlag(.Verbose))
					writer.Sizer((.)count, true);

				Array(writer, t.UnderlyingType, val.DataPtr, count, env);
			}
			else if (TypeHoldsObject!(valType))
			{
				if (*(void**)val.DataPtr == null)
					writer.Null();
				else
				{
					let polyType = (*(Object*)val.DataPtr).GetType();
					if (polyType != valType)
					{
						Debug.Assert(!polyType.IsObject || polyType.IsSubtypeOf(valType) || (valType.IsInterface && polyType.HasInterface(valType)));

						// Change type of pointer to actual type
						val.UnsafeSetType(polyType);

						let typeName = polyType.GetFullName(.. scope .());
						writer.Type(typeName);
					}
					else Debug.Assert(!valType.IsInterface);

					if (!polyType.IsObject)
					{
						// @report currently we
						// hack together a pointer of the payload, as
						// currently the box doesn't have reflection when
						// they payload does. If that gets fixed, the box
						// has a "val" field which we would get the offset of
						// -> we do the same thing in Deserialize.bf
						let boxedPtr = (uint8*)*(void**)val.DataPtr + sizeof(int) // mClassVData
#if BF_DEBUG_ALLOC
							+ sizeof(int) // mDebugAllocInfo
#endif
							;

						Debug.Assert(!polyType.IsObject);

						// polyType already is the type in the box
						var boxedData = Variant.CreateReference(polyType, boxedPtr);
						Value(writer, ref boxedData, env);

						// After this we only end the line but the Value call
						// above has already done that.
						return;
					}
					else if (polyType == typeof(String))
					{
						let str = val.Get<String>();
						writer.String(str);
					}
					else if (polyType.IsArray)
					{
						Debug.Assert(polyType != typeof(Array) && polyType is ArrayType);

						let t = polyType as ArrayType;
						
						Debug.Assert(t.GetField("mFirstElement") case .Ok, "No reflection data forced for array type!\n(for example: [Serializable] extension Array1<T> {} or through build settings)");

						let arrType = t.GetGenericArg(0); // T
						let classData = *(uint8**)val.DataPtr;
						var arrPtr = classData + t.GetField("mFirstElement").Get().MemberOffset; // T*

						// @report: *(int_strsize*)(classData + typeof(Array).GetField("mLength").Get().MemberOffset)
						// doesnt work, seems like the field is never reflected, also doesnt work with t.GetField("mLength")
						var count = val.Get<Array>().Count;
						
						mixin GetLenField(String field)
						{
							*(int_arsize*)(classData + t.GetField(field).Get().MemberOffset)
						}

						switch (t.UnspecializedType)
						{
						case typeof(Array1<>):
							writer.Sizer((.)count);
							Array(writer, arrType, arrPtr, count, env);

						case typeof(Array2<>):
							let count1 = GetLenField!("mLength1");
							count /= count1;
							writer.MultiSizer((.)count,(.)count1);

							MultiDimensionalArray(writer, arrType, arrPtr, env, count, count1);

						case typeof(Array3<>):
							let count2 = GetLenField!("mLength2");
							let count1 = GetLenField!("mLength1");
							count /= (count1 * count2);
							writer.MultiSizer((.)count,(.)count1,(.)count2);

							MultiDimensionalArray(writer, arrType, arrPtr, env, count, count1, count2);

						case typeof(Array4<>):
							let count1 = GetLenField!("mLength1");
							let count2 = GetLenField!("mLength2");
							let count3 = GetLenField!("mLength3");
							count /= (count1 * count2 * count3);
							writer.MultiSizer((.)count,(.)count1,(.)count2,(.)count3);

							MultiDimensionalArray(writer, arrType, arrPtr, env, count, count1, count2, count3);

						default:
							Debug.FatalError();
						}
					}
					// TODO consider using interfaces like ICollection<> and so on and using that? -> should also work for structs i guess? but not now
					// or just use custom stuff right away
					/*else if (let t = valType as SpecializedGenericType && t == typeof(List<>))
					{
						Debug.FatalError(); // List<>, HashSet<>, Dictionary<,>
					}*/
					else Class(writer, ref val, env);
				}
			}
			else if (valType.IsPointer)
			{
				// also handle references to ourselves
				// however we detect that. -> of base structure if struct put mem ptr + size as range or on reftype put instance ptr + size as bounds for checking
				// put & and field path in there?
				// also do this... for classes? -- hash pointers+size (as range test) we've included with some info or something??

				Debug.FatalError(); // TODO
			}
			else Debug.FatalError();

			writer.EntryEnd(doOneLine);
		}

		public static void Class(BonWriter writer, ref Variant classVal, BonEnvironment env)
		{
			let classType = classVal.VariantType;

			Debug.Assert(classType.IsObject);

			var classDataVal = Variant.CreateReference(classType, *(void**)classVal.DataPtr);
			Struct(writer, ref classDataVal, env);
		}

		public static void Struct(BonWriter writer, ref Variant structVal, BonEnvironment env)
		{
			let structType = structVal.VariantType;

			bool hasUnnamedMembers = false;
			using (writer.ObjectBlock())
			{
				if (structType.FieldCount > 0)
				{
					for (let m in structType.GetFields(.Instance))
					{
						let flags = env.serializeFlags;
						if ((!flags.HasFlag(.IgnoreAttributes) && m.GetCustomAttribute<NoSerializeAttribute>() case .Ok) // check hidden
							|| !flags.HasFlag(.IncludeNonPublic) && (m.[Friend]mFieldData.mFlags & .Public == 0) // check protection level
							&& (flags.HasFlag(.IgnoreAttributes) || !(m.GetCustomAttribute<DoSerializeAttribute>() case .Ok))) // check if we still include it anyway
							continue;

						Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

						if (!DoInclude!(ref val, flags))
							continue;

						if (flags.HasFlag(.Verbose) && uint64.Parse(m.Name) case .Ok)
							hasUnnamedMembers = true;

						writer.Identifier(m.Name);
						Value(writer, ref val, env);
					}
				}
			}

			if (env.serializeFlags.HasFlag(.Verbose))
			{
				// Just add this as a comment in case anyone wonders...
				if (!structType is TypeInstance)
					writer.outStr.Append(scope $"/* No reflection data for {structType}. Add [Serializable] or force it */");
				else if (hasUnnamedMembers)
					writer.outStr.Append(scope $"/* Type has unnamed members */");
			}
		}

		public static void Array(BonWriter writer, Type arrType, void* arrPtr, int count, BonEnvironment env)
		{
			let doArrayOneLine = DoTypeOneLine!(arrType, env.serializeFlags);
			using (writer.ArrayBlock(doArrayOneLine))
			{
				if (count > 0)
				{
					var includeCount = count;
					if (!env.serializeFlags.HasFlag(.IncludeDefault)) // DoInclude! would return true on anything anyway
					{
						var ptr = (uint8*)arrPtr + arrType.Stride * (count - 1);
						for (var i = count - 1; i >= 0; i--)
						{
							var arrVal = Variant.CreateReference(arrType, ptr);

							// If this gets included, we'll have to include everything until here!
							if (DoInclude!(ref arrVal, env.serializeFlags))
							{
								includeCount = i + 1;
								break;
							}

							ptr -= arrType.Stride;
						}
					}

					var ptr = (uint8*)arrPtr;
					for (let i < includeCount)
					{
						var arrVal = Variant.CreateReference(arrType, ptr);
						if (DoInclude!(ref arrVal, env.serializeFlags))
							Value(writer, ref arrVal, env, doArrayOneLine);
						else
						{
							// Shorten this... as mentioned in Thing() we don't automatically place default, but ?
							Irrelevant(writer);
						}

						ptr += arrType.Stride;
					}
				}
			}
		}

		public static void MultiDimensionalArray(BonWriter writer, Type arrType, void* arrPtr, BonEnvironment env, params int[] counts)
		{
			Debug.Assert(counts.Count > 1); // Must be multi-dimensional!

			let count = counts[0];
			var stride = counts[1];
			if (counts.Count > 2)
				for (let i < counts.Count - 2)
					stride *= counts[i + 2];
			stride *= arrType.Stride;

			using (writer.ArrayBlock())
			{
				if (count > 0)
				{
					var includeCount = count;
					if (!env.serializeFlags.HasFlag(.IncludeDefault))
					{
						var ptr = (uint8*)arrPtr + stride * (count - 1);
						DEFCHECK:for (var i = count - 1; i >= 0; i--)
						{
							// If this gets included, we'll have to include everything until here!
							for (var j < stride)
								if (ptr[j] != 0)
									break DEFCHECK;

							includeCount = i + 1;
							ptr -= stride;
						}
					}

					var ptr = (uint8*)arrPtr;
					for (let i < includeCount)
					{
						bool isZero = true;
						for (var j < stride)
							if (ptr[j] != 0)
							{
								isZero = false;
								break;
							}

						if (!isZero || env.serializeFlags.HasFlag(.IncludeDefault))
						{
							let inner = counts.Count - 1;
							if (inner > 1)
							{
								int[] innerCounts = scope .[inner];
								for (let j < inner)
									innerCounts[j] = counts[j + 1];

								MultiDimensionalArray(writer, arrType, ptr, env, params innerCounts);
							}
							else Array(writer, arrType, ptr, counts[1], env);

							writer.EntryEnd();
						}	
						else
						{
							// Shorten this... as mentioned in Thing() we don't automatically place default, but ?
							Irrelevant(writer);
						}

						ptr += stride;
					}
				}
			}
		}

		[Inline]
		public static void Irrelevant(BonWriter writer)
		{
			writer.EntryStart();
			writer.IrrelevantEntry();
			writer.EntryEnd();
		}

		static mixin AsThingToString<T>(BonWriter writer, ref Variant val)
		{
			T thing = *(T*)val.DataPtr;
			thing.ToString(writer.outStr);
		}

		[Inline]
		static void Integer(Type type, BonWriter writer, ref Variant val)
		{
			switch (type)
			{
			case typeof(int8): AsThingToString!<int8>(writer, ref val);
			case typeof(int16): AsThingToString!<int16>(writer, ref val);
			case typeof(int32): AsThingToString!<int32>(writer, ref val);
			case typeof(int64): AsThingToString!<int64>(writer, ref val);
			case typeof(int): AsThingToString!<int>(writer, ref val);

			case typeof(uint8): AsThingToString!<uint8>(writer, ref val);
			case typeof(uint16): AsThingToString!<uint16>(writer, ref val);
			case typeof(uint32): AsThingToString!<uint32>(writer, ref val);
			case typeof(uint64): AsThingToString!<uint64>(writer, ref val);
			case typeof(uint): AsThingToString!<uint>(writer, ref val);

			default: Debug.FatalError(); // Should be unreachable
			}
		}

		[Inline]
		static void Char(Type type, BonWriter writer, ref Variant val)
		{
			char32 char = 0;
			switch (type)
			{
			case typeof(char8): char = (.)*(char8*)val.DataPtr;
			case typeof(char16): char = (.)*(char16*)val.DataPtr;
			case typeof(char32): char = *(char32*)val.DataPtr;
			}
			writer.Char(char);
		}

		[Inline]
		static void Float(Type type, BonWriter writer, ref Variant val)
		{
			switch (type)
			{
			case typeof(float): AsThingToString!<float>(writer, ref val);
			case typeof(double): AsThingToString!<double>(writer, ref val);

			default: Debug.FatalError(); // Should be unreachable
			}
		}

		[Inline]
		static void Bool(BonWriter writer, ref Variant val, BonSerializeFlags flags)
		{
			bool boolean = *(bool*)val.DataPtr;
			if (flags.HasFlag(.Verbose))
				boolean.ToString(writer.outStr);
			else (boolean ? 1 : 0).ToString(writer.outStr);
		}
	}
}