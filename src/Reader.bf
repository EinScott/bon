using System;
using System.Diagnostics;

namespace Bon.Integrated
{
	class BonReader
	{
		public struct ArrayBlockEnd : IDisposable
		{
			BonReader r;

			[Inline]
			public this(BonReader format)
			{
				r = format;
			}

			[Inline]
			public bool HasMore()
			{
				return !r.Check(']');
			}

			[Inline]
			public void Dispose()
			{
				r.ArrayBlockEnd();
			}
		}

		public struct ObjectBlockEnd : IDisposable
		{
			BonReader r;

			[Inline]
			public this(BonReader format)
			{
				r = format;
			}

			[Inline]
			public bool HasMore()
			{
				return !r.Check('}');
			}

			[Inline]
			public void Dispose()
			{
				r.ObjectBlockEnd();
			}
		}

		public StringView inStr;
		int objDepth, arrDepth;
		public enum Errors
		{
			None = 0,
			UnterminatedComment = 1,
			ExpectedArray = 1 << 2,
			UnterminatedArray = 1 << 3,
			ExpectedObject = 1 << 4,
			UnterminatedObject = 1 << 5,
			ExpectedString = 1 << 6,
			UnterminatedString = 1 << 7,
			ExpectedChar = 1 << 8,
			UnterminatedChar = 1 << 9,
			ExpectedSizer = 1 << 10,
			UnterminatedSizer = 1 << 11,
			ExpectedComma = 1 << 12,
			ExpectedEquals = 1 << 13
		}
		public Errors errors;

		[Inline]
		public this(StringView str)
		{
			Debug.Assert(str.Ptr != null);

			inStr = str;

			ConsumeEmpty();
		}

		void ConsumeEmpty()
		{
			// Skip space, line breaks, tabs and comments
			var i = 0;
			var commentDepth = 0;
			bool lineComment = false;
			let len = inStr.Length; // Since it won't be change in the following loop...
			for (; i < len; i++)
			{
				let char = inStr[[Unchecked]i];
				if (lineComment)
				{
					if (char == '\n')
						lineComment = false;

					// Ignore this
				}
				if (!char.IsWhiteSpace)
				{
					if (i + 1 < len)
					{
						if (char == '/')
						{
							if (inStr[[Unchecked]i + 1] == '*')
							{
								commentDepth++;
								i++;
								continue;
							}
							else if (inStr[[Unchecked]i + 1] == '/')
							{
								lineComment = true;
								i++;
								continue;
							}
						}
						else if (char == '*' && inStr[[Unchecked]i + 1] == '/')
						{
							commentDepth--;
							i++;
							continue;
						}	
					}

					if (commentDepth == 0)
						break;
				}
			}
			Debug.Assert(commentDepth >= 0);

			if (commentDepth > 0)
				errors |= .UnterminatedComment; // TODO: tests for things like these! also unexpected string ends!!

			inStr.RemoveFromStart(i);
		}

		[Inline]
		public bool HadErrors()
		{
			return errors != .None;
		}

		[Inline]
		public bool ReachedEnd()
		{
			return inStr.Length == 0;
		}

		bool Check(char8 token, bool consume = true)
		{
			if (inStr.StartsWith(token))
			{
				if (consume)
					inStr.RemoveFromStart(1);
				return true;
			}
			else return false;
		}

		StringView ParseName()
		{
			var nameLen = 0;
			for (; nameLen < inStr.Length; nameLen++)
			{
				let char = inStr[nameLen];
				if (!char.IsLetterOrDigit && char != '_')
					break;
			}

			let name = inStr.Substring(0, nameLen);
			inStr.RemoveFromStart(nameLen);
			return name;
		}

		public StringView Integer()
		{
			var numLen = 0;
			if (inStr.Length > 0 && inStr[0] == '-')
				numLen++;
			while (inStr.Length > numLen + 1 &&  inStr[numLen].IsNumber)
				numLen++;

			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen);

			ConsumeEmpty();

			return num;
		}

		public StringView Floating()
		{
			var numLen = 0;
			while ({
				let char = inStr[numLen];
				inStr.Length > numLen + 1 && char.IsNumber || char == '.' || char == '-' || char == 'e'
			})
				numLen++;

			if (inStr.StartsWith('f') || inStr.StartsWith('d'))
				inStr.RemoveFromStart(1);

			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen);

			ConsumeEmpty();

			return num;
		}

		public StringView String()
		{
			if (!Check('"', false))
			{
				errors |= .ExpectedString;
				return default;
			}

			var strLen = 0;
			bool isEscaped = false;
			while (inStr.Length > strLen && (isEscaped || !Check('"')))
			{
				isEscaped = inStr[strLen] == '\\' && !isEscaped;
				strLen++;
			}

			if (!Check('"', false))
			{
				errors |= .UnterminatedString;
				return default;
			}

			let str = String.UnQuoteString(&inStr[0], strLen, .. scope .());
			inStr.RemoveFromStart(strLen);

			ConsumeEmpty();

			return str;
		}

		public Result<char32> Char()
		{
			if (!Check('\'', false))
			{
				errors |= .ExpectedString;
				return .Err;
			}
			else inStr[0] = '"';

			// TODO: also parse unicode notation

			var strLen = 0;
			bool isEscaped = false;
			while (inStr.Length > strLen && (isEscaped || !Check('\'')))
			{
				isEscaped = inStr[strLen] == '\\' && !isEscaped;
				strLen++;
			}

			let strBegin = &inStr[0];
			inStr.RemoveFromStart(strLen);

			if (!Check('\'', false))
			{
				errors |= .UnterminatedString;
				return .Err;
			}
			else inStr[0] = '"';
			inStr.RemoveFromStart(1);

			let str = String.UnQuoteString(strBegin, strLen, .. scope .());
			if (str.Length > 4)
				return .Err;

			char32 char = 0;
			Internal.MemCpy(&char, &str[0], str.Length);

			ConsumeEmpty();

			return char;
		}

		public Result<bool> Bool()
		{
			if (Check('0'))
				return false;
			else if (Check('1'))
				return false;
			else if (inStr.StartsWith(bool.TrueString, .OrdinalIgnoreCase))
			{
				inStr.RemoveFromStart(4);
				return true;
			}
			else if (inStr.StartsWith(bool.FalseString, .OrdinalIgnoreCase))
			{
				inStr.RemoveFromStart(4);
				return false;
			}

			return .Err;
		}

		public StringView Identifier()
		{
			let name = ParseName();

			ConsumeEmpty();

			if (!Check('='))
				errors |= .ExpectedEquals;

			ConsumeEmpty();

			return name;
		}

		public ArrayBlockEnd ArrayBlock()
		{
			if (!Check('['))
				errors |= .ExpectedArray;

			ConsumeEmpty();

			return .(this);
		}

		public ObjectBlockEnd ObjectBlock()
		{
			if (!Check('{'))
				errors |= .ExpectedObject;

			ConsumeEmpty();

			return .(this);
		}
		
		void ArrayBlockEnd()
		{
			if (!Check(']'))
				errors |= .UnterminatedArray;

			ConsumeEmpty();
		}

		void ObjectBlockEnd()
		{
			if (!Check('}'))
				errors |= .UnterminatedObject;

			ConsumeEmpty();
		}

		public void EntryEnd()
		{
			if (!Check(','))
				errors |= .UnterminatedObject;

			ConsumeEmpty();
		}
	}
}