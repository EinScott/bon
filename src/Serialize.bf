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

	// TODO: implement verbosity (smallbools, small enums) + size prefixes

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

		static mixin DoInclude(ref Variant val, BonSerializeFlags includeFlags)
		{
			(includeFlags.HasFlag(.IncludeDefault) || !VariantDataIsZero!(val))
		}

		[Inline]
		public static void Thing(BonWriter writer, ref Variant thingVal, BonSerializeFlags includeFlags = .DefaultFlags)
		{
			if (DoInclude!(ref thingVal, includeFlags))
				Field(writer, ref thingVal, includeFlags);
		}

		public static void Struct(BonWriter writer, ref Variant structVal, BonSerializeFlags includeFlags = .DefaultFlags)
		{
			let structType = structVal.VariantType;

			Debug.Assert(structType.IsStruct);

			if (!structType is TypeInstance
				|| (structType.FieldCount == 0 && !structType.HasCustomAttribute<SerializableAttribute>()))
			{
				BonConfig.logOut?.Invoke(scope $"Struct {structType} does not seem to have reflection data included. Add [Serializable]");

				// In case we do include default values (and thus expect to have everything in there),
				// still include "{}"
				if (!includeFlags.HasFlag(.IncludeDefault))
					return;
			}

			using (writer.StartObject())
			{
				if (structType.FieldCount > 0)
				{
					for (let m in structType.GetFields(.Instance))
					{
						if ((!includeFlags.HasFlag(.IgnoreAttributes) && m.GetCustomAttribute<NoSerializeAttribute>() case .Ok) // check hidden
							|| !includeFlags.HasFlag(.AllowNonPublic) && (m.[Friend]mFieldData.mFlags & .Public == 0) // check protection level
							&& (includeFlags.HasFlag(.IgnoreAttributes) || !(m.GetCustomAttribute<DoSerializeAttribute>() case .Ok))) // check if we still include it anyway
							continue;

						Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

						if (!DoInclude!(ref val, includeFlags))
							continue;

						writer.Identifier(m.Name);
						Field(writer, ref val, includeFlags);
					}
				}
			}
		}

		public static void Field(BonWriter writer, ref Variant val, BonSerializeFlags includeFlags = .DefaultFlags, bool doOneLineVal = false)
		{
			let fieldType = val.VariantType;
			let valueBuffer = scope String();

			mixin AsThingToString<T>()
			{
				T integer = *(T*)val.DataPtr;
				integer.ToString(valueBuffer);
			}

			if (fieldType.IsEnum)
			{
				if (fieldType.IsUnion)
				{
					Debug.FatalError(); // TODO
				}
				else
				{
					valueBuffer.Append('.');
					int64 value = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&value, fieldType.Size));
					Enum.EnumToString(fieldType, valueBuffer, value);

					// TODO: some effort to try and convert number values into combinations of named values?
				}
			}
			else if (fieldType.IsInteger ||
				fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsInteger)
			{
				

				switch (fieldType)
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
			else if (fieldType.IsFloatingPoint
				|| fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsFloatingPoint)
			{
				switch (fieldType)
				{
				case typeof(float): AsThingToString!<float>();
				case typeof(double): AsThingToString!<double>();

				default: Debug.FatalError(); // Should be unreachable
				}
			}
			else if (fieldType == typeof(bool))
			{
				AsThingToString!<bool>();
			}
			else if (fieldType is SizedArrayType)
			{
				using (writer.StartArray())
				{
					let t = (SizedArrayType)fieldType;
					let count = t.ElementCount;
					if (count > 0)
					{
						let arrType = t.UnderlyingType;
						let doOneLine = (arrType.IsPrimitive || arrType.IsTypedPrimitive);

						var includeCount = count;
						if (!includeFlags.HasFlag(.IncludeDefault))
						{
							var ptr = (uint8*)val.DataPtr + arrType.Stride * (count - 1);
							for (var i = count - 1; i >= 0; i--)
							{
								var arrVal = Variant.CreateReference(arrType, ptr);

								// If this gets included, we'll have to include everything until here!
								if (DoInclude!(ref arrVal, includeFlags))
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
							Field(writer, ref arrVal, includeFlags, doOneLine);

							ptr += arrType.Stride;
						}
					}
				}

				return; // we don't need buffer
			}
			else if (fieldType == typeof(StringView))
			{
				let view = val.Get<StringView>();

				if (view.Ptr == null)
					valueBuffer.Append("null");
				else if (view.Length == 0)
					valueBuffer.Append("\"\"");
				else String.QuoteString(&view[0], view.Length, valueBuffer);
			}
			else if (fieldType == typeof(String))
			{
				let str = val.Get<String>();

				if (str == null)
					valueBuffer.Append("null");
				else if (str.Length == 0)
					valueBuffer.Append("\"\"");
				else String.QuoteString(&str[0], str.Length, valueBuffer);
			}
			else if (fieldType.IsStruct)
			{
				Struct(writer, ref val, includeFlags);
				return;
			}
			else
			{
				Debug.FatalError(scope $"Couldn't serialize field of type {fieldType.GetName(.. scope .())}");
				return;
			}

			writer.Value(valueBuffer, doOneLineVal);
		}
	}
}