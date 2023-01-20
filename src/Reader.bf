using System;
using System.Collections;
using System.Diagnostics;

using internal Bon;

namespace Bon.Integrated
{
	class BonReader
	{
		public StringView inStr;
		internal StringView origStr;
		int objDepth, arrDepth;

		[Inline]
		public Result<void> Setup(BonContext con)
		{
			Debug.Assert(con.strLeft.Ptr != null);

			inStr = con.strLeft;
			origStr = con.origStr;

			if (!con.hasMore)
				Error!("Expected entry.");

			return .Ok;
		}

		/// Intended for error report. Get current line and trim to around current pos
		public void GetCurrentPos(String buffer)
		{
			if (origStr.Ptr == null || inStr.Ptr == null)
				return;

			var currPos = Math.Min(origStr.Length - inStr.Length, origStr.Length - 1);
			if (currPos == -1)
			{
				buffer.Append("\n> (string is empty)");
				return;
			}

			// Often time we have already discarded the empty space after a thing and are
			// at the start of the next thing. Dial back until we point at something again!
			for (; currPos > 0; currPos--)
			{
				let char = origStr[currPos];
				if (!(char.IsControl || char.IsWhiteSpace))
					break;
			}

			var start = currPos;
			bool startCapped = false;
			for (var dist = 0; start >= 0; start--, dist++)
			{
				if (origStr[start] == '\n')
					break;

				if (dist == 64)
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

				if (dist == 32)
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

			buffer.Append("(line ");
			lines.ToString(buffer);
			buffer.Append(")\n");
			
			buffer.Append("> ");
			if (startCapped)
				buffer.Append("...");

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
				buffer.Append("...");

			buffer.Append("\n> ");
			if (startCapped)
				buffer.Append("   ");

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
			Deserialize.Error!(error, this);
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
				else if (!char.IsWhiteSpace)
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
								if (commentDepth == 0)
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
			// */ shouldn't even be recognized on its own and
			// does not count as empty space
			Debug.Assert(commentDepth >= 0);
			
			if (commentDepth > 0)
				Error!("Unterminated comment");

			inStr.RemoveFromStart(i);

			return .Ok;
		}

		/// Parses contents until an *actual* endChar on the same scope level, which it does not include in len.
		/// Error checking can be performed on all the return params. DID NOT FIND endChar IF LEN == inStr.Len
		public (int len, int bracketDepth, int commentDepth, bool str, bool char, bool lineComment, bool isEmpty) SkipContentsUntil(int startIdx, params char8[] endChars)
		{
			if (inStr.Length <= 0)
				return default;

			let strLen = inStr.Length;
			bool isEmpty = true;
			int i = startIdx;
			int bracketDepth = 0, commentDepth = 0;
			bool str = false, verbStr = false, char = false, escaped = false, lineComment = false;
			PARSE:while (i < strLen)
			{
				let c = inStr[[Unchecked]i];

				// We've found an *actual* endChar on the same scope level
				if (!str && !char && !lineComment && commentDepth == 0 && bracketDepth == 0)
				{
					for (let ec in endChars)
						if (c == ec)
							break PARSE;
				}

				bool doResetEscape = true, doCheckContent = true;
				switch (c)
				{
				case '[', '{':
					if (!str && !char && !lineComment && commentDepth == 0)
						bracketDepth++;
				case ']', '}':
					if (!str && !char && !lineComment && commentDepth == 0)
						bracketDepth--;
					
				case '\'':
					if (!str && !escaped && !lineComment && commentDepth == 0)
						char = !char;
				case '"':
					if (!char && !escaped && !lineComment && commentDepth == 0)
					{
						if (!str)
							verbStr = i > 0 && inStr[[Unchecked]i - 1] == '@';

						str = !str;
					}
				case '\\':
					if (!escaped && (char || str && !verbStr) && !lineComment && commentDepth == 0)
					{
						escaped = true;

						// Don't reset escaped right away
						doResetEscape = false;
					}
				case '/':
					if (!str && !char && i + 1 < strLen && !lineComment)
					{
						let next = inStr[[Unchecked]i + 1];

						if (next == '*')
						{
							commentDepth++;
							i++;
						}
						else if (next == '/')
						{
							if (commentDepth == 0)
								lineComment = true;
							i++;
						}

						// If any of the above bodies was run, we're now in
						// a comment, which will fail the content check
					}
				case '*':
					if (!str && !char && i + 1 < strLen && commentDepth > 0)
					{
						let next = inStr[[Unchecked]i + 1];
						if (next == '/')
						{
							commentDepth--;
							i++;

							// Maybe we're not in a comment anymore. But
							// don't count this as content yet
							doCheckContent = false;
						}	
					}
				case '\n':
					lineComment = false;
				}

				if (escaped && doResetEscape)
					escaped = false;

				if (isEmpty && doCheckContent && !lineComment && commentDepth == 0 && !c.IsWhiteSpace)
					isEmpty = false;

				i++;

				if (commentDepth < 0 || bracketDepth < 0)
					break;
			}

			return (i - startIdx, bracketDepth, commentDepth, str, char, lineComment, isEmpty);
		}

		[Inline]
		public bool ReachedEnd()
		{
			return inStr.Length == 0 && objDepth == 0 && arrDepth == 0;
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

		public Result<void> Pair()
		{
			if (!Check(':'))
				Error!("Expected value pair");

			return ConsumeEmpty();
		}

		public Result<StringView> Integer()
		{
			var numLen = 0;
			bool hasHex = false, isNegative = false;
			if (inStr.Length > 0 && (inStr[0] == '-' || inStr[0] == '+'))
			{
				numLen++;
				isNegative = inStr[0] == '-';
			}

			if (inStr.Length > numLen + 1 && inStr[numLen] == '0')
			{
				let c = inStr[numLen + 1];
				if (c == 'b' || c == 'o')
					numLen += 2;
				else if (c == 'x')
				{
					hasHex = true;
					numLen += 2;
				}
			}

			while (inStr.Length > numLen && (inStr[numLen].[Inline]IsNumber
				|| hasHex && { let c = inStr[numLen]; ((c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')) }
				|| numLen > 0 && inStr[numLen] == '\''))
				numLen++;

			// Take care of suffix. The number parser
			// doesnt actually need to know about this
			int suffLen = 0;
			bool l = false, u = false;
			while (inStr.Length > numLen + suffLen)
			{
				let c = inStr[numLen + suffLen].ToLower;
				if (c == 'u' && !u)
				{
					if (isNegative)
					{
						inStr.RemoveFromStart(numLen + suffLen);
						Error!("Negative integer cannot be unsigned");
					}
					u = true;
				}
				else if (c == 'l' && !l)
					l = true;
				else break;

				suffLen++;
			}

			if (numLen == 0)
				Error!("Expected integer");
			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen + suffLen);

			Try!(ConsumeEmpty());

			return num;
		}

		public Result<StringView> Floating()
		{
			let nanSymbol = "NaN";
			let infSymbol = "Infinity";

			int numLen = 0;
			bool hasValue = true;
			if (inStr.Length > 0)
			{
				if (inStr.StartsWith(nanSymbol, .OrdinalIgnoreCase))
					numLen = nanSymbol.Length;
				else if (inStr.StartsWith(infSymbol, .OrdinalIgnoreCase))
					numLen = infSymbol.Length;
				else if ((inStr[0] == '-' || inStr[0] == '+') && inStr.Substring(1).StartsWith(infSymbol, .OrdinalIgnoreCase))
					numLen = infSymbol.Length + 1;
				else
				{
					hasValue = false; // Prove it!
					while (inStr.Length > numLen && {
						let char = inStr[numLen];
						hasValue |= char.IsNumber;
						char.IsNumber || char == '.' || char == '-' || char == '+' || char.ToLower == 'e'
					})
						numLen++;
				}
			}

			if (numLen == 0 || !hasValue)
				Error!("Expected floating point");

			let num = inStr.Substring(0, numLen);
			inStr.RemoveFromStart(numLen);
			if (inStr.StartsWith('f') || inStr.StartsWith('d'))
				inStr.RemoveFromStart(1);

			Try!(ConsumeEmpty());

			return num;
		}

		public Result<(int len, bool isVerbatim)> StringLength()
		{
			let isVerbatim = Check('@');

			if (inStr.Length == 0 || !Check('"'))
				Error!("Expected string");

			var strLen = 0;
			bool isEscaped = false;
			while (strLen < inStr.Length && (isEscaped || inStr[strLen] != '"'))
			{
				let char = inStr[strLen];
				isEscaped = char == '\\' && !isEscaped && !isVerbatim;

				if ((char >= (char8)0) && (char <= (char8)0x1F) && char != '\t')
				{
					inStr.RemoveFromStart(strLen - 1);
					if (char == '\n') // Specify since it's easily confusing as it counts as white space
						Error!("Newline not allowed in string. Use escape sequence");
					else Error!("Char not allowed in string. Use escape sequence");
				}

				strLen++;
			}

			if (strLen >= inStr.Length)
				Error!("Unterminated string");

			return .Ok((strLen, isVerbatim));
		}

		public Result<void> String(String into, int parsedStrLen, bool isVerbatim)
		{
			let stringContent = StringView(&inStr[0], parsedStrLen);

			if (!isVerbatim)
			{
				if (String.UnQuoteStringContents(stringContent, into) case .Err(let errPos))
				{
					inStr.RemoveFromStart(errPos);
					Error!("Invalid escape sequence");
				}
			}
			else into.Append(stringContent);

			inStr.RemoveFromStart(parsedStrLen);

			if (!Check('\"'))
				Debug.FatalError(); // Should not happen, since otherwise strLen would go on until the end of the string!

			return ConsumeEmpty();
		}

		public Result<int> SubfileStringLength()
		{
			Try!(ConsumeEmpty());
			Try!(ArrayBlock());

			let res = SkipContentsUntil(0, ']');

			if (res.str)
				Error!("Unterminated string in sub-file string");
			else if (res.char)
				Error!("Unterminated char in sub-file string");
			else if (res.lineComment || res.commentDepth != 0)
				Error!("Unbalanced comment in sub-file string");
			else if (res.bracketDepth != 0)
				Error!("Unbalanced bracket in sub-file string");
			else if (res.len >= inStr.Length)
				Error!("Unterminated sub-file string");

			return .Ok(res.len);
		}

		public Result<void> SubfileString(String into, int parsedStrLen)
		{
			into.Append(StringView(&inStr[0], parsedStrLen)..Trim());
			inStr.RemoveFromStart(parsedStrLen);

			return ArrayBlockEnd();
		}

		public Result<char32> Char()
		{
			if (inStr.Length == 0 || !Check('\''))
				Error!("Expected char");

			var strLen = 0;
			bool isEscaped = false;
			while (strLen < inStr.Length && (isEscaped || inStr[strLen] != '\''))
			{
				let char = inStr[strLen];
				isEscaped = char == '\\' && !isEscaped;
				if ((char >= (char8)0) && (char <= (char8)0x1F))
					Error!("Char not allowed. Use escape sequence");
				strLen++;
			}

			if (strLen >= inStr.Length)
			{
				if (strLen > 0)
					inStr.RemoveFromStart(inStr.Length - 1);
				Error!("Unterminated char");
			}	

			let stringContent = StringView(&inStr[0], strLen);

			let str = scope String();
			if (String.UnQuoteStringContents(stringContent, str) case .Err(let errPos))
			{
				inStr.RemoveFromStart(errPos);
				Error!("Invalid escape sequence");
			}	

			if (str.Length > 4)
				Error!("Oversized char");
			else if (str.Length == 0)
				Error!("Empty char");

			let res = str.GetChar32(0);
			if (res.length != str.Length)
				Error!("Multiple chars in char");
			
			inStr.RemoveFromStart(strLen);

			if (!Check('\''))
				Debug.FatalError(); // Should not happen, since otherwise strLen would go on until the end of the string!

			Try!(ConsumeEmpty());

			return .Ok(res.c);
		}

		public Result<bool> Bool()
		{
			if (Check('1'))
			{
				Try!(ConsumeEmpty());
				return true;
			}
			else if (Check('0'))
			{
				Try!(ConsumeEmpty());
				return false;
			}
			else if (inStr.StartsWith(bool.TrueString, .OrdinalIgnoreCase))
			{
				inStr.RemoveFromStart(4);
				Try!(ConsumeEmpty());
				return true;
			}
			else if (inStr.StartsWith(bool.FalseString, .OrdinalIgnoreCase))
			{
				inStr.RemoveFromStart(5);
				Try!(ConsumeEmpty());
				return false;
			}

			Error!("Expected bool");
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

		public bool IsNull(bool consumeIfFound = true)
		{
			if (inStr.StartsWith("null"))
			{
				if (consumeIfFound)
					inStr.RemoveFromStart(4);
				return true;
			}
			return false;
		}

		public bool IsDefault(bool consumeIfFound = true)
		{
			if (inStr.StartsWith("default"))
			{
				if (consumeIfFound)
					inStr.RemoveFromStart(7);
				return true;
			}
			return false;
		}

		public bool IsIrrelevantEntry()
		{
			return Check('?');
		}

		[Inline]
		public bool IsSubfile()
		{
			return Check('$');
		}

		[Inline]
		public bool IsTyped()
		{
			return Check('(', false);
		}

		public Result<StringView> Type()
		{
			if (!Check('('))
				Error!("Expected type marker");
			Try!(ConsumeEmpty());

			var nameLen = 0;
			var bracketDepth = 0;
			for (; nameLen < inStr.Length; nameLen++)
			{
				let char = inStr[nameLen];

				if (char.IsWhiteSpace || (char == ')' && bracketDepth == 0))
					break;
				else
				{
					if (char == '(')
						bracketDepth++;
					else if (char == ')')
						bracketDepth--;
				}
			}
			Debug.Assert(bracketDepth == 0);

			let name = inStr.Substring(0, nameLen);
			inStr.RemoveFromStart(nameLen);

			if (name.Length == 0)
				Error!("Epected type name");

			Try!(ConsumeEmpty());

			if (!Check(')'))
				Error!("Unterminated type marker");

			Try!(ConsumeEmpty());

			return name;
		}

		[Inline]
		public bool IsReference()
		{
			return Check('&', false);
		}

		public Result<StringView> Reference()
		{
			if (!Check('&'))
				Error!("Expected type marker");

			var refLen = 0;
			for (; refLen < inStr.Length; refLen++)
			{
				let char = inStr[refLen];
				if (!char.IsLetterOrDigit && char != '_')
					break;
			}

			let reference = inStr.Substring(0, refLen);
			inStr.RemoveFromStart(refLen);

			Try!(ConsumeEmpty());

			return reference;
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

		public bool ArrayHasSizer()
		{
			return Check('<', false);
		}

		public Result<StringView[N]> ArraySizer<N>(bool constValid) where N : const int
		{
			if (!Check('<'))
				Error!("Expected array sizer");

			Try!(ConsumeEmpty());

			if (inStr.StartsWith("const"))
			{
				if (constValid)
					inStr.RemoveFromStart(5);
				else Error!("Sizer of dynamic array cannot be const");

				Try!(ConsumeEmpty());
			}

			StringView[N] ints = default;
			for (let i < N)
			{
				let int = Try!(Integer());
				if (int.StartsWith('-'))
					Error!("Expected positive integer");

				ints[i] = int;

				if (i + 1 < N)
				{
					if (!Check(','))
						Error!("Incomplete array sizer");
					Try!(ConsumeEmpty());
				}
			}	 

			if (!Check('>'))
				Error!("Unterminated array sizer");

			Try!(ConsumeEmpty());

			return ints;
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
			return !Check(']', false) && inStr.Length > 0;
		}

		[Inline]
		public bool ObjectHasMore()
		{
			return !Check('}', false) && inStr.Length > 0;
		}

		public Result<int64> ArrayPeekCount()
		{
			// Validates the top-structure of the array and basic integrity of entrires.

			int i = 0;
			int64 count = 0;
			let len = inStr.Length;

			// Advance until opening [
			while (i < len && inStr[[Unchecked]i] != '[')
				i++;
			i++; // Pass it

			mixin DoErr(String str)
			{
				inStr.RemoveFromStart(i);
				Error!(str);
			}

			if (i >= len)
				DoErr!("Expected array");

			bool wasEmpty = true;
			while (i < len)
			{
				// Skip array entry until ,
				let res = SkipContentsUntil(i, ',', ']');

				if (res.str)
					DoErr!("Unterminated string in array element");
				else if (res.char)
					DoErr!("Unterminated char in array element");
				else if (res.lineComment || res.commentDepth != 0)
					DoErr!("Unbalanced comment in array element");
				else if (res.bracketDepth != 0)
					DoErr!("Unbalanced brackets in array element");

				i += res.len;
				count++;
				if (!res.isEmpty)
					wasEmpty = false;

				if (i >= len)
					DoErr!("Unterminated array");

				if (inStr[[Unchecked]i] == ',')
				{
					if (res.isEmpty)
						DoErr!("Empty array element");

					i++;
				}
				else
				{
					if (res.isEmpty)
						count--; // Trailing comma

					Debug.Assert(inStr[[Unchecked]i] ==  ']');
					break;
				}
			}
			if (i >= len)
				DoErr!("Unterminated array");

			if (wasEmpty && count == 1)
				count = 0;

			return count;
		}

		public Result<void> EntryEnd()
		{
			if (!Check(','))
				Error!("Expected comma");

			return ConsumeEmpty();
		}

		public Result<int64> FileEntryPeekCount()
		{
			int i = 0;
			int64 count = 0;
			let len = inStr.Length;
			bool wasEmpty = true;

			mixin DoErr(String str)
			{
				inStr.RemoveFromStart(i);
				Error!(str);
			}

			while (i < len)
			{
				// Skip array entry until , (or eof)
				let res = SkipContentsUntil(i, ',');

				if (res.str)
					DoErr!("Unterminated string in entry");
				else if (res.char)
					DoErr!("Unterminated char in entry");
				else if (res.lineComment || res.commentDepth != 0)
					DoErr!("Unbalanced comment in entry");
				else if (res.bracketDepth != 0)
					DoErr!("Unbalanced brackets in entry");

				i += res.len;
				count++;
				if (!res.isEmpty)
					wasEmpty = false;

				if (i >= len)
				{
					if (res.isEmpty)
						count--; // Trailing comma
				}
				else
				{
					if (res.isEmpty)
						DoErr!("Empty entry");

					Debug.Assert(inStr[[Unchecked]i] == ',');
					i++;
				}
			}

			if (wasEmpty && count == 1)
				count = 0;

			return count;
		}

		public Result<void> FileEntrySkip(int skipCount)
		{
			Debug.Assert(skipCount >= 0);

			if (skipCount == 0)
				return .Ok;
			
			int i = 0;
			int64 count = 0;
			let len = inStr.Length;
			bool wasEmpty = true;

			mixin DoErr(String str)
			{
				inStr.RemoveFromStart(i);
				Error!(str);
			}

			while (i < len)
			{
				// Skip array entry until , (or eof)
				let res = SkipContentsUntil(i, ',');

				if (res.str)
					DoErr!("Unterminated string in entry");
				else if (res.char)
					DoErr!("Unterminated char in entry");
				else if (res.lineComment || res.commentDepth != 0)
					DoErr!("Unbalanced comment in entry");
				else if (res.bracketDepth != 0)
					DoErr!("Unbalanced brackets in entry");

				i += res.len;
				count++;
				if (!res.isEmpty)
					wasEmpty = false;

				if (i >= len)
				{
					if (res.isEmpty)
						count--; // Trailing comma
				}
				else
				{
					if (res.isEmpty)
						DoErr!("Empty entry");

					Debug.Assert(inStr[[Unchecked]i] == ',');
					i++;
				}
				
				if (count == skipCount)
				{
					inStr.RemoveFromStart(i);
					return .Ok;
				}
			}

			if (!wasEmpty && count == 1)
			{
				// This will be the end...
				inStr.RemoveFromStart(i);
				return .Ok;
			}
			Error!("Not enough entries found to skip");
		}

		public Result<void> FileEntryEnd()
		{
			if (!Check(','))
				Error!("Expected comma");

			if (objDepth != 0 || arrDepth != 0)
				Error!("Unbalanced brackets");

			return .Ok;
		}
	}
}