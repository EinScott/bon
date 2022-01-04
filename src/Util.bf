namespace System
{
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
					case '\'': outString.Append("'");
					case '\"': outString.Append("\"");
					case '\\': outString.Append("\\");
					case '0': outString.Append("\0");
					case 'a': outString.Append("\a");
					case 'b': outString.Append("\b");
					case 'f': outString.Append("\f");
					case 'n': outString.Append("\n");
					case 'r': outString.Append("\r");
					case 't': outString.Append("\t");
					case 'v': outString.Append("\v");
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