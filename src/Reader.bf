using System;
using System.Collections;
using System.Diagnostics;

namespace Bon.Integrated
{
	class BonReader
	{
		public StringView inStr;
		StringView origStr;
		int objDepth, arrDepth;

		[Inline]
		public this(StringView str)
		{
			Debug.Assert(str.Ptr != null);

			inStr = str;
			origStr = str;
		}

		/// Intended for error report. Get current line and trim to around current pos
		public void GetCurrentPos(String buffer)
		{
			let currPos = Math.Min(origStr.Length - inStr.Length, origStr.Length - 1);

			var start = currPos;
			bool startCapped = false;
			for (var dist = 0; start >= 0; start--, dist++)
			{
				if (origStr[start] == '\n')
					break;

				if (dist == 51)
				{
					startCapped = true;
					break;
				}
			}
			if (start != currPos)
				start++;

			var end = currPos;
			bool endCapped = false;
			for (var dist = 0; end < origStr.Length; end++, dist++)
			{
				if (origStr[end] == '\n')
					break;

				if (dist == 26)
				{
					endCapped = true;
					break;
				}
			}
			if (end != currPos)
				end--;

			int lines = 1;
			for (var i = start; i >= 0; i--)
			{
				if (origStr[i] == '\n')
					lines++;
			}

			var pad = currPos - start;
			if (startCapped)
				pad += 6;

			buffer.Append("(line ");
			lines.ToString(buffer);
			buffer.Append(")\n");
			
			buffer.Append("> ");
			if (startCapped)
				buffer.Append("[...] ");

			var part = origStr.Substring(start, end - start + 1);
			if (part.StartsWith("\n"))
				part.RemoveFromStart(1);
			
			for (let c in part)
			{
				if (!c.IsControl || c == '\t')
					buffer.Append(c);
				else pad--;
			}

			if (endCapped)
				buffer.Append(" [...]");

			buffer.Append("\n> ");

			for (let i < pad)
			{
				let char = origStr[start + i];
				if (char == '\t')
					buffer.Append('\t');
				else buffer.Append(' ');
			}
			buffer.Append('^');
		}

		mixin Error(String error)
		{
			Deserialize.Error!(this, error);
		}

		public Result<void> ConsumeEmpty()
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
				Error!("Unterminated comment");

			inStr.RemoveFromStart(i);

			return .Ok;
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

		public Result<StringView> Integer()
		{
			var numLen = 0;
			if (inStr.Length > 0 && inStr[0] == '-')
				numLen++;
			while (inStr.Length > numLen &&  inStr[numLen].IsNumber)
				numLen++;

			if (numLen == 0)
				Error!("Expected integer literal");
			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen);

			Try!(ConsumeEmpty());

			return num;
		}

		public Result<StringView> Floating()
		{
			var numLen = 0;
			while ({
				let char = inStr[numLen];
				inStr.Length > numLen && char.IsNumber || char == '.' || char == '-' || char == 'e'
			})
				numLen++;

			if (numLen == 0)
				Error!("Expected floating point literal");

			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen);
			if (inStr.StartsWith('f') || inStr.StartsWith('d'))
				inStr.RemoveFromStart(1);

			Try!(ConsumeEmpty());

			return num;
		}

		public Result<StringView> String()
		{
			if (inStr.Length == 0 || !Check('"'))
				Error!("Expected string literal");

			var strLen = 0;
			bool isEscaped = false;
			while (strLen < inStr.Length && (isEscaped || inStr[strLen] != '"'))
			{
				isEscaped = inStr[strLen] == '\\' && !isEscaped;
				strLen++;
			}

			if (strLen >= inStr.Length)
			{
				if (strLen > 0)
					inStr.RemoveFromStart(inStr.Length - 1);
				Error!("Unterminated string literal");
			}	

			let stringContent = StringView(&inStr[0], strLen);

			let str = scope String();
			if (String.UnQuoteStringContents(stringContent, str) case .Err)
				Error!("Invalid string literal");

			inStr.RemoveFromStart(strLen);

			if (!Check('\"'))
				Debug.FatalError(); // Should not happen, since otherwise strLen would go on until the end of the string!

			Try!(ConsumeEmpty());

			return .Ok(str);
		}

		public Result<char32> Char()
		{
			if (inStr.Length == 0 || !Check('\''))
				Error!("Expected char literal");

			var strLen = 0;
			bool isEscaped = false;
			while (strLen < inStr.Length && (isEscaped || inStr[strLen] != '\''))
			{
				isEscaped = inStr[strLen] == '\\' && !isEscaped;
				strLen++;
			}

			if (strLen >= inStr.Length)
			{
				if (strLen > 0)
					inStr.RemoveFromStart(inStr.Length - 1);
				Error!("Unterminated char literal");
			}	

			let stringContent = StringView(&inStr[0], strLen);

			let str = scope String();
			if (String.UnQuoteStringContents(stringContent, str) case .Err)
				Error!("Invalid char literal");

			if (str.Length > 4)
				Error!("Oversized char literal");
			else if (str.Length == 0)
				Error!("Empty char literal");

			let res = str.GetChar32(0);
			if (res.length != str.Length)
				Error!("Too many chars in char literal");
			
			inStr.RemoveFromStart(strLen);

			if (!Check('\''))
				Debug.FatalError(); // Should not happen, since otherwise strLen would go on until the end of the string!

			Try!(ConsumeEmpty());

			return .Ok(res.c);
		}

		public Result<bool> Bool()
		{
			if (Check('1'))
				return true;
			else if (Check('0'))
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

			Error!("Expected bool literal");
		}

		public Result<StringView> Identifier()
		{
			let name = ParseName();
			if (name.Length == 0)
				Error!("Expected identifier name");

			Try!(ConsumeEmpty());

			if (!Check('='))
				Error!("Expected equals");

			Try!(ConsumeEmpty());

			return name;
		}

		public bool HasNull(bool consumeIfFound = true)
		{
			if (inStr.StartsWith("null"))
			{
				if (consumeIfFound)
					inStr.RemoveFromStart(4);
				return true;
			}
			return false;
		}

		[Inline]
		public bool EnumHasNamed()
		{
			return inStr.Length > 1 && inStr[1].IsLetter // Don't mistake .95f as a named enum value!
				&& Check('.');
		}

		[Inline]
		public Result<void> EnumNext()
		{
			return ConsumeEmpty();
		}

		[Inline]
		public Result<StringView> EnumName()
		{
			let name = ParseName();
			if (name.Length == 0)
				Error!("Expected enum case name");

			Try!(ConsumeEmpty());

			return name;
		}

		[Inline]
		public bool EnumHasMore()
		{
			return Check('|');
		}

		public Result<void> ArrayBlock()
		{
			if (!Check('['))
				Error!("Expected array");

			return ConsumeEmpty();
		}

		public Result<void> ObjectBlock()
		{
			if (!Check('{'))
				Error!("Expected object");

			return ConsumeEmpty();
		}
		
		public Result<void> ArrayBlockEnd()
		{
			if (!Check(']'))
				Error!("Unterminated array");

			return ConsumeEmpty();
		}

		public Result<void> ObjectBlockEnd()
		{
			if (!Check('}'))
				Error!("Unterminated object");

			return ConsumeEmpty();
		}

		[Inline]
		public bool ArrayHasMore()
		{
			return !Check('}', false);
		}

		[Inline]
		public bool ObjectHasMore()
		{
			return !Check('}', false);
		}

		public Result<void> EntryEnd()
		{
			if (!Check(','))
				Error!("Expected comma");

			return ConsumeEmpty();
		}
	}
}