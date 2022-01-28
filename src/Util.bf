using System;

namespace Bon.Integrated
{
	static
	{
		public static mixin VariantDataIsZero(Variant val)
		{
			bool isZero = true;
			var ptr = (uint8*)val.DataPtr;
			let size = val.VariantType.Size;
			switch (size)
			{
			case 0:
			case 1: isZero = *ptr == 0;
			case 2: isZero = *(uint16*)ptr == 0;
			case 4: isZero = *(uint32*)ptr == 0;
			case 8: isZero = *(uint64*)ptr == 0;
			default:
				for (var i < size)
					if (ptr[i] != 0)
						isZero = false;
			}
			isZero
		}

		public static mixin TypeHoldsObject(Type type)
		{
			(type.IsObject || type.IsInterface)
		}
	}
}

namespace System
{
	extension Type
	{
		public bool HasInterface(Type interfaceType)
		{
			for (let i in Interfaces)
				if (i == interfaceType)
					return true;
			return false;
		}
	}

	extension Variant
	{
		[Inline]
		public void UnsafeSetType(Type type) mut
		{
			mStructType = ((int)Internal.UnsafeCastToPtr(type) & ~3) | mStructType & 3;
		}
	}

	extension String
	{
		public static Result<void> UnQuoteStringContents(StringView view, String outString)
		{
			var ptr = view.Ptr;
			char8* endPtr = view.EndPtr;

			while (ptr < endPtr)
			{
				char8 c = *(ptr++);
				if (c == '\\')
				{
					if (ptr == endPtr)
						return .Err;

					char8 nextC = *(ptr++);
					switch (nextC)
					{
					case '\'': outString.Append('\'');
					case '\"': outString.Append('"');
					case '\\': outString.Append('\\');
					case '0': outString.Append('\0');
					case 'a': outString.Append('\a');
					case 'b': outString.Append('\b');
					case 'f': outString.Append('\f');
					case 'n': outString.Append('\n');
					case 'r': outString.Append('\r');
					case 't': outString.Append('\t');
					case 'v': outString.Append('\v');
					case 'x':
						// TODO
					case 'u':
						// TODO
					default:
						return .Err;
					}
					continue;
				}

				outString.Append(c);
			}

			return .Ok;
		}
	}
}