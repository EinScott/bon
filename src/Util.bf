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
		public static Result<void, int> UnQuoteStringContents(StringView view, String outString)
		{
			var ptr = view.Ptr;

			mixin Err()
			{
				return .Err(ptr - view.Ptr);
			}

			char8* endPtr = view.EndPtr;

			while (ptr < endPtr)
			{
				char8 c = *(ptr++);
				if (c == '\\')
				{
					if (ptr == endPtr)
						Err!();

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
						uint8 num = 0;
						for (let i < 2)
						{
							if (ptr == endPtr)
								Err!();
							let hexC = *(ptr++);

							if ((hexC >= '0') && (hexC <= '9'))
								num = num*0x10 + (uint8)(hexC - '0');
							else if ((hexC >= 'A') && (hexC <= 'F'))
								num = num*0x10 + (uint8)(c - 'A') + 10;
							else if ((hexC >= 'a') && (hexC <= 'f'))
								num = num*0x10 + (uint8)(hexC - 'a') + 10;
							else Err!();
						}

						outString.Append((char8)num);

					case 'u':
						if (ptr == endPtr)
							Err!();

						char8 uniC = *(ptr++);
						if (uniC != '{')
							Err!();

						uint32 num = 0;
						for (let i < 7)
						{
							if (ptr == endPtr)
								Err!();
							uniC = *(ptr++);

							if (uniC == '}')
							{
								if (i == 0)
									Err!();
								break;
							}
							else if (i == 7)
								Err!();

							if ((uniC >= '0') && (uniC <= '9'))
								num = num*0x10 + (uint32)(uniC - '0');
							else if ((uniC >= 'A') && (uniC <= 'F'))
								num = num*0x10 + (uint32)(uniC - 'A') + 10;
							else if ((uniC >= 'a') && (uniC <= 'f'))
								num = num*0x10 + (uint32)(uniC - 'a') + 10;
							else Err!();
						}

						if (num > 0x10FFFF)
							Err!();

						outString.Append((char32)num);

					default:
						Err!();
					}
					continue;
				}

				outString.Append(c);
			}

			return .Ok;
		}
	}
}