using System;
using System.Diagnostics;

namespace Bon.Integrated
{
	class BonWriter
	{
		public struct ArrayBlockEnd : IDisposable
		{
			BonWriter w;
			bool oneLine;

			[Inline]
			public this(BonWriter format, bool doOneLine)
			{
				w = format;
				oneLine = doOneLine;
			}

			[Inline]
			public void Dispose()
			{
				w.ArrayBlockEnd(oneLine);
			}
		}

		public struct ObjectBlockEnd : IDisposable
		{
			BonWriter w;

			[Inline]
			public this(BonWriter format)
			{
				w = format;
			}

			[Inline]
			public void Dispose()
			{
				w.ObjectBlockEnd();
			}
		}

		struct FormatHelper
		{
			int tabDepth;

			[Inline]
			public void TabPush() mut
			{
				tabDepth++;
			}

			[Inline]
			public void TabPop() mut
			{
				tabDepth--;

				Debug.Assert(tabDepth >= 0);
			}

			[Inline]
			public void DoTabs(String outStr)
			{
				for (let i < tabDepth)
					outStr.Append('\t');
			}

			[Inline]
			public void NewLine(String outStr)
			{
				outStr.Append('\n');
			}
		}

		public String outStr;
		bool doFormatting;
		
		FormatHelper f;
		int objDepth, arrDepth;

		[Inline]
		public this(String str, bool formatting = false)
		{
			Debug.Assert(str != null);

			outStr = str;
			doFormatting = formatting;
		}

		public void Identifier(StringView identifier)
		{
			Debug.Assert(!outStr.EndsWith('=') && !outStr.EndsWith(':'));

			if (doFormatting)
				f.DoTabs(outStr);
			outStr.Append(identifier);
			if (doFormatting)
				outStr.Append(' ');
			outStr.Append('=');
			if (doFormatting)
				outStr.Append(' ');
		}

		[Inline]
		public void Pair()
		{
			Debug.Assert(!outStr.EndsWith('=') && !outStr.EndsWith(':'));

			if (outStr.EndsWith(','))
				outStr.RemoveFromEnd(1);
			else if (doFormatting && outStr.EndsWith(",\n"))
				outStr.RemoveFromEnd(2);

			outStr.Append(':');
			if (doFormatting)
				outStr.Append(' ');
		}

		[Inline]
		public void EntryStart(bool doOneLine = false)
		{
			if (doFormatting && !doOneLine && outStr.EndsWith('\n'))
				f.DoTabs(outStr);
		}

		[Inline]
		public void Enum(StringView caseName)
		{
			if (outStr.Length != 0 && { let char = outStr[outStr.Length - 1]; char.IsLetterOrDigit || char == '\'' })
				EnumAdd();
			outStr..Append('.').Append(caseName);
		}

		[Inline]
		public void EnumAdd()
		{
			outStr.Append('|');
		}

		[Inline]
		public void Sizer(uint64 count, bool markConst = false)
		{
			outStr.Append('<');
			if (markConst)
				outStr.Append("const ");
			count.ToString(outStr);
			outStr.Append('>');	
		}

		public void MultiSizer<N>(params uint64[N] counts) where N : const int
		{
			outStr.Append('<');
			for (let i < N)
			{
				counts[i].ToString(outStr);
				if (i + 1 < N)
					outStr.Append(',');
			}
			outStr.Append('>');	
		}

		[Inline]
		public void String(StringView string)
		{
			if (string.Length == 0)
				outStr.Append("\"\"");
			else String.Quote(&string[[Unchecked]0], string.Length, outStr);
		}

		[Inline]
		public void Null()
		{
			outStr.Append("null");
		}

		[Inline]
		public void Reference(StringView referencePath)
		{
			outStr..Append('&')..Append(referencePath);
		}

		[Inline]
		public void Type(StringView typeName)
		{
			outStr..Append('(')..Append(typeName)..Append(')');
		}

		[Inline]
		public void Char(char32 char)
		{
			outStr.Append('\'');
			let string = scope String()..Append(char);
			let len = string.Length;
			String.Escape(&string[[Unchecked]0], len, outStr);
			outStr.Append('\'');
		}

		[Inline]
		public void Bool(bool bool)
		{
			outStr.Append(bool ? "true" : "false");
		}

		[Inline]
		public void IrrelevantEntry()
		{
			outStr.Append('?');
		}

		public void Start()
		{
			if (outStr.Length > 0)
			{
				outStr.Append(',');
				if (doFormatting)
					f.NewLine(outStr);
			}
		}

		public ArrayBlockEnd ArrayBlock(bool doOneLine = false)
		{
			outStr.Append('[');
			if (doFormatting)
			{
				if (!doOneLine)
					f.NewLine(outStr);
				f.TabPush();
			}

			arrDepth++;

			return .(this, doOneLine);
		}

		public ObjectBlockEnd ObjectBlock()
		{
			outStr.Append('{');
			if (doFormatting)
			{
				f.NewLine(outStr);
				f.TabPush();
			}

			objDepth++;

			return .(this);
		}

		void ArrayBlockEnd(bool doOneLine)
		{
			Debug.Assert(arrDepth > 0);
			arrDepth--;

			if (outStr.EndsWith(','))
				outStr.RemoveFromEnd(1);
			if (doFormatting)
			{
				if (outStr.EndsWith(",\n"))
					outStr..RemoveFromEnd(2).Append('\n');

				f.TabPop();
				if (!doOneLine)
					f.DoTabs(outStr);
			}

			outStr.Append(']');
		}

		void ObjectBlockEnd()
		{
			Debug.Assert(objDepth > 0);
			objDepth--;

			if (doFormatting)
			{
				f.TabPop();

				if (outStr.EndsWith(",\n")) // Trailing ", "
				{
					outStr..RemoveFromEnd(2).Append('\n');
					f.DoTabs(outStr);
				}	
				else if (outStr.EndsWith("{\n")) // Empty object "{\n"
					outStr.RemoveFromEnd(1);
				else
				{
					f.DoTabs(outStr);
				}
			}
			else if (outStr.EndsWith(','))
				outStr.RemoveFromEnd(1);

			outStr.Append('}');
		}
		
		public void EntryEnd(bool doOneLine = false)
		{
			if (!doFormatting)
			{
				if (!outStr.EndsWith(','))
					outStr.Append(',');
			}
			else
			{
				if (!outStr.EndsWith(",\n") || outStr.EndsWith(','))
				{
					outStr.Append(',');
					if (!doOneLine)
						f.NewLine(outStr);
				}
			}
		}

		public void End()
		{
			Debug.Assert(objDepth == 0 && arrDepth == 0);

			if (outStr.Length > 0)
			{
				// Remove trailing newline with tabs (possibly)
				while (outStr[[Unchecked]outStr.Length - 1].IsWhiteSpace)
					outStr.RemoveFromEnd(1);

				if (outStr.EndsWith(','))
					outStr.RemoveFromEnd(1);
			}
		}
	}
}
