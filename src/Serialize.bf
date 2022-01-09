using System;
using System.Diagnostics;
using System.Reflection;

namespace Bon.Integrated
{
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

		static mixin DoTypeOneLine(Type type, BonSerializeFlags flags)
		{
			(type.IsPrimitive || (type.IsTypedPrimitive && (!flags.HasFlag(.Verbose) || !type.IsEnum)))
		}

		public static void Thing(BonWriter writer, ref Variant val, BonSerializeFlags flags = .Default)
		{
			if (DoInclude!(ref val, flags))
				Value(writer, ref val, flags);
			writer.End();
			if (flags.HasFlag(.Verbose) && writer.outStr.Length == 0)
				writer.outStr.Append("/* value is default */");
		}

		public static void Value(BonWriter writer, ref Variant val, BonSerializeFlags flags = .Default, bool doOneLine = false)
		{
			let valType = val.VariantType;

			// Make sure that doOneLineVal is only passed when valid
			Debug.Assert(!doOneLine || DoTypeOneLine!(valType, flags));

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
					Bool(writer, ref val, flags);
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{
				// Is used to change what will be printed if the enum has a remainder
				// to be printed as a literal
				int64 enumRemainderVal = 0;
				var printVal = val;

				bool doPrintLiteral = true;
				if (valType.IsEnum && flags.HasFlag(.Verbose))
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

								// Print remainder literal below!
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
						Bool(writer, ref printVal, flags);
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
							Struct(writer, ref unionPayload, flags);

							didWrite = true;
							break;
						}
					}

					Debug.Assert(didWrite);
				}
				else Struct(writer, ref val, flags);
			}
			else if (valType is SizedArrayType)
			{
				let t = (SizedArrayType)valType;
				let count = t.ElementCount;
				if (count > 0)
				{
					// Since this is a fixed-size array, this info is not necessary to
					// deserialize in any case. But it's nice for manual editing to know how
					// much the array can hold
					if (flags.HasFlag(.Verbose))
						writer.Sizer((.)count, true);
					
					let arrType = t.UnderlyingType;
					let doArrayOneLine = DoTypeOneLine!(arrType, flags);
					using (writer.ArrayBlock(doArrayOneLine))
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
							Value(writer, ref arrVal, flags, doArrayOneLine);

							ptr += arrType.Stride;
						}
					}
				}
			}
			else if (valType.IsObject)
			{
				if (valType == typeof(String))
				{
					let str = val.Get<String>();

					if (str == null)
						writer.Null();
					else writer.String(str);
				}
				else Class(writer, ref val, flags);
			}
			else if (valType.IsPointer)
			{
				Debug.FatalError(); // TODO
			}
			else Debug.FatalError();

			writer.EntryEnd(doOneLine);
		}

		public static void Class(BonWriter writer, ref Variant classVal, BonSerializeFlags flags = .Default)
		{
			let classType = classVal.VariantType;

			Debug.Assert(classType.IsObject);

			let classPtr = (void**)classVal.DataPtr;
			if (classPtr == null)
			{
				writer.Null();
			}
			else
			{
				var classDataVal = Variant.CreateReference(classType, *classPtr);
				Struct(writer, ref classDataVal, flags);
			}
		}

		public static void Struct(BonWriter writer, ref Variant structVal, BonSerializeFlags flags = .Default)
		{
			let structType = structVal.VariantType;

			bool hasUnnamedMembers = false;
			using (writer.ObjectBlock())
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

						if (flags.HasFlag(.Verbose) && uint64.Parse(m.Name) case .Ok)
							hasUnnamedMembers = true;

						writer.Identifier(m.Name);
						Value(writer, ref val, flags);
					}
				}
			}

			if (flags.HasFlag(.Verbose))
			{
				// Just add this as a comment in case anyone wonders...
				if (!structType is TypeInstance)
					writer.outStr.Append(scope $"/* No reflection data for {structType}. Add [Serializable] or force it */");
				else if (hasUnnamedMembers)
					writer.outStr.Append(scope $"/* Type has unnamed members */");
			}
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