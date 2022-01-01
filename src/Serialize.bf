using System;
using System.Diagnostics;
using System.Reflection;

namespace Bon.Integrated
{
	public enum BonSerializeFlags : uint8
	{
		public static Self DefaultFlags = Default;

		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields
		case AllowNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		/// Ignore field attributes (only recommended for debugging / complete structure dumping)
		case IgnoreAttributes = 1 << 2;

		/// The produced string will be suitable (and slightly more verbose) for manual editing.
		case Verbose = 1 << 3;
	}

	static class Serialize
	{
		static mixin VariantDataIsZero(Variant val)
		{
			bool isZero = true;
			for (var i < val.VariantType.Size)
				if (((uint8*)val.DataPtr)[i] != 0)
					isZero = false;
			isZero
		}

		static mixin DoInclude(ref Variant val, BonSerializeFlags flags)
		{
			(flags.HasFlag(.IncludeDefault) || !VariantDataIsZero!(val))
		}

		[Inline]
		public static void Thing(BonWriter writer, ref Variant thingVal, BonSerializeFlags flags = .DefaultFlags)
		{
			if (DoInclude!(ref thingVal, flags))
				Field(writer, ref thingVal, flags);
		}

		static mixin DoTypeOneLine(Type type, BonSerializeFlags flags)
		{
			(type.IsPrimitive || (type.IsTypedPrimitive && (!flags.HasFlag(.Verbose) || !type.IsEnum)))
		}

		public static void Field(BonWriter writer, ref Variant val, BonSerializeFlags flags = .DefaultFlags, bool doOneLineVal = false)
		{
			let fieldType = val.VariantType;

			// Make sure that doOneLineVal is only passed when valid
			Debug.Assert(!doOneLineVal || DoTypeOneLine!(fieldType, flags));

			mixin AsThingToString<T>()
			{
				T thing = *(T*)val.DataPtr;
				thing.ToString(writer.outStr);
			}

			mixin Integer(Type type)
			{
				switch (type)
				{
				case typeof(int8): AsThingToString!<int8>();
				case typeof(int16): AsThingToString!<int16>();
				case typeof(int32): AsThingToString!<int32>();
				case typeof(int64): AsThingToString!<int64>();
				case typeof(int): AsThingToString!<int>();

				case typeof(uint8): AsThingToString!<uint8>();
				case typeof(uint16): AsThingToString!<uint16>();
				case typeof(uint32): AsThingToString!<uint32>();
				case typeof(uint64): AsThingToString!<uint64>();
				case typeof(uint): AsThingToString!<uint>();

				default: Debug.FatalError(); // Should be unreachable
				}
			}

			mixin Char(Type type)
			{
				mixin HandleChar<T>()
				{
					T thing = *(T*)val.DataPtr;
					var str = thing.ToString(.. scope .());
					let len = str.Length;
					String.QuoteString(&str[0], len, str);
					writer.outStr.Append(str[(len + 1)...^2]);
				}

				writer.outStr.Append('\'');
				switch (type)
				{
				case typeof(char8): HandleChar!<char8>();
				case typeof(char16): HandleChar!<char16>();
				case typeof(char32): HandleChar!<char32>();
				}
				writer.outStr.Append('\'');
			}

			mixin Float(Type type)
			{
				switch (type)
				{
				case typeof(float): AsThingToString!<float>();
				case typeof(double): AsThingToString!<double>();

				default: Debug.FatalError(); // Should be unreachable
				}
			}

			mixin Bool()
			{
				bool boolean = *(bool*)val.DataPtr;
				if (flags.HasFlag(.Verbose))
					boolean.ToString(writer.outStr);
				else (boolean ? 1 : 0).ToString(writer.outStr);
			}

			if (fieldType.IsPrimitive)
			{
				writer.StartLine(doOneLineVal);

				if (fieldType.IsInteger)
					Integer!(fieldType);
				else if (fieldType.IsFloatingPoint)
					Float!(fieldType);
				else if (fieldType.IsChar)
					Char!(fieldType);
				else if (fieldType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (fieldType.IsTypedPrimitive)
			{
				writer.StartLine(doOneLineVal);

				if (fieldType.UnderlyingType.IsInteger)
				{
					if (fieldType.IsEnum && flags.HasFlag(.Verbose))
					{
						int64 value = 0;
						Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&value, fieldType.Size));

						bool found = false;
						for (var field in fieldType.GetFields())
						{
							if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase) &&
								*(int64*)&field.[Friend]mFieldData.[Friend]mData == value)
							{
								writer.outStr..Append('.').Append(field.Name);
								found = true;
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
							int64 valueLeft = value;
							String bestValName = scope .();
							while (valueLeft != 0)
							{
								// Go through all values and find best match in therms of bits
								int64 bestVal = 0;
								var bestValBits = 0;
								for (var field in fieldType.GetFields())
								{
									if (field.[Friend]mFieldData.mFlags.HasFlag(.EnumCase))
									{
										let fieldVal = *(int64*)&field.[Friend]mFieldData.[Friend]mData;

										if (fieldVal == 0 || (fieldVal & ~valueLeft) != 0)
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
									valueLeft &= ~bestVal; // Remove all bits it shares with this
									writer.outStr..Append('.')..Append(bestValName).Append('|');
								}
								else
								{
									if (writer.outStr.EndsWith('|')) // Flags enum
										(*(uint64*)&valueLeft).ToString(writer.outStr, "X", null);
									else Integer!(fieldType.UnderlyingType);
									break;
								}

								if (valueLeft == 0)
								{
									if (writer.outStr.EndsWith('|'))
										writer.outStr.RemoveFromEnd(1);
									break;
								}
							}
						}

					}
					else Integer!(fieldType.UnderlyingType);
				}
				else if (fieldType.UnderlyingType.IsFloatingPoint)
					Float!(fieldType.UnderlyingType);
				else if (fieldType.UnderlyingType.IsChar)
					Char!(fieldType.UnderlyingType);
				else if (fieldType.UnderlyingType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (fieldType.IsStruct)
			{
				if (fieldType == typeof(StringView))
				{
					writer.StartLine(doOneLineVal);

					let view = val.Get<StringView>();

					if (view.Ptr == null)
						writer.outStr.Append("null");
					else if (view.Length == 0)
						writer.outStr.Append("\"\"");
					else String.QuoteString(&view[0], view.Length, writer.outStr);
				}
				else if (fieldType.IsEnum && fieldType.IsUnion)
				{
					// Enum union in memory:
					// {<payload>|<discriminator>}

					bool didWrite = false;
					uint64 unionCaseIndex = uint64.MaxValue;
					uint64 currCaseIndex = 0;
					for (var enumField in fieldType.GetFields())
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
						}
						else if (enumField.[Friend]mFieldData.mFlags.HasFlag(.EnumCase)) // Filter through unioncaseIndex
						{
							Debug.Assert(unionCaseIndex != uint64.MaxValue);

							// Skip enum cases until we get to the selected one
							if (currCaseIndex != unionCaseIndex)
							{
								currCaseIndex++;
								continue;
							}

							var unionPayload = Variant.CreateReference(enumField.FieldType, val.DataPtr);

							// Do serialize of discriminator and payload
							writer.outStr..Append('.').Append(enumField.Name);
							Struct(writer, ref unionPayload, flags);

							didWrite = true;
							break;
						}
					}

					Debug.Assert(didWrite);
				}
				else Struct(writer, ref val, flags);
			}
			else if (fieldType is SizedArrayType)
			{
				let t = (SizedArrayType)fieldType;
				let count = t.ElementCount;
				if (count > 0)
				{
					// Since this is a fixed-size array, this info is not necessary to
					// deserialize in any case. But it's nice for manual editing to know how
					// much the array can hold
					if (flags.HasFlag(.Verbose))
					{
						writer.outStr.Append("<const ");
						count.ToString(writer.outStr);
						writer.outStr.Append('>');
					}
					
					let arrType = t.UnderlyingType;
					let doOneLine = DoTypeOneLine!(arrType, flags);
					using (writer.StartArray(doOneLine))
					{
						var includeCount = count;
						if (!flags.HasFlag(.IncludeDefault))
						{
							var ptr = (uint8*)val.DataPtr + arrType.Stride * (count - 1);
							for (var i = count - 1; i >= 0; i--)
							{
								var arrVal = Variant.CreateReference(arrType, ptr);

								// If this gets included, we'll have to include everything until here!
								if (DoInclude!(ref arrVal, flags))
								{
									includeCount = i + 1;
									break;
								}

								ptr -= arrType.Stride;
							}
						}

						var ptr = (uint8*)val.DataPtr;
						for (let i < includeCount)
						{
							var arrVal = Variant.CreateReference(arrType, ptr);
							Field(writer, ref arrVal, flags, doOneLine);

							ptr += arrType.Stride;
						}
					}
				}
			}
			else if (fieldType == typeof(String))
			{
				writer.StartLine(doOneLineVal);

				let str = val.Get<String>();

				if (str == null)
					writer.outStr.Append("null");
				else if (str.Length == 0)
					writer.outStr.Append("\"\"");
				else String.QuoteString(&str[0], str.Length, writer.outStr);
			}
			else Debug.FatalError(); // TODO

			writer.EndEntry(doOneLineVal);
		}

		public static void Struct(BonWriter writer, ref Variant structVal, BonSerializeFlags flags = .DefaultFlags)
		{
			let structType = structVal.VariantType;

			Debug.Assert(structType.IsStruct);

			using (writer.StartObject())
			{
				if (structType.FieldCount > 0)
				{
					for (let m in structType.GetFields(.Instance))
					{
						if ((!flags.HasFlag(.IgnoreAttributes) && m.GetCustomAttribute<NoSerializeAttribute>() case .Ok) // check hidden
							|| !flags.HasFlag(.AllowNonPublic) && (m.[Friend]mFieldData.mFlags & .Public == 0) // check protection level
							&& (flags.HasFlag(.IgnoreAttributes) || !(m.GetCustomAttribute<DoSerializeAttribute>() case .Ok))) // check if we still include it anyway
							continue;

						Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

						if (!DoInclude!(ref val, flags))
							continue;

						writer.Identifier(m.Name);
						Field(writer, ref val, flags);
					}
				}
			}

			if (!structType is TypeInstance)
			{
				// Just add this as a comment in case anyone wonders...
				writer.outStr.Append(scope $"/* No reflection data for {structType}. Add [Serializable] or force it */");
			}
		}
	}
}