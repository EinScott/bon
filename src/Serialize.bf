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

		public static void Field(BonWriter writer, ref Variant val, BonSerializeFlags flags = .DefaultFlags, bool doOneLineVal = false)
		{
			let fieldType = val.VariantType;

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
				if (fieldType.IsInteger)
					Integer!(fieldType);
				else if (fieldType.IsFloatingPoint)
					Float!(fieldType);
				else if (fieldType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (fieldType.IsTypedPrimitive)
			{
				if (fieldType.UnderlyingType.IsInteger)
				{
					if (fieldType.IsEnum && flags.HasFlag(.Verbose))
					{
						writer.outStr.Append('.');
						int64 value = 0;
						Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&value, fieldType.Size));
						Enum.EnumToString(fieldType, writer.outStr, value);

						// TODO: some effort to try and convert number values into combinations of named values?
					}
					else Integer!(fieldType.UnderlyingType);
				}
				else if (fieldType.UnderlyingType.IsFloatingPoint)
					Float!(fieldType.UnderlyingType);
				else if (fieldType.UnderlyingType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (fieldType.IsStruct)
			{
				if (fieldType == typeof(StringView))
				{
					let view = val.Get<StringView>();

					if (view.Ptr == null)
						writer.outStr.Append("null");
					else if (view.Length == 0)
						writer.outStr.Append("\"\"");
					else String.QuoteString(&view[0], view.Length, writer.outStr);
				}
				else if (fieldType.IsEnum && fieldType.IsUnion)
				{
					Debug.FatalError(); // TODO (also check, is this even reachable and in the right place?)
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
						writer.outStr.Append('<');
						count.ToString(writer.outStr);
						writer.outStr.Append("> /* sized array! */"); // No use changing the count number!
					}
	
					using (writer.StartArray())
					{
						let arrType = t.UnderlyingType;
						let doOneLine = (arrType.IsPrimitive || arrType.IsTypedPrimitive);

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

			if (!structType is TypeInstance
					|| (structType.FieldCount == 0 && !structType.HasCustomAttribute<SerializableAttribute>()))
			{
				// Just add this as a comment in case anyone wonders...
				writer.outStr.Append(scope $"/* No reflection data for {structType}. Add [Serializable] or force it */");
			}
		}
	}
}