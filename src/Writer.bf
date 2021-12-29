using System;
using System.Diagnostics;
using System.IO;

namespace Bon.Integrated
{
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

	struct ArrayBlockEnd : IDisposable
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
			w.EndArray();
		}
	}

	struct ObjectBlockEnd : IDisposable
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
			w.EndObject();
		}
	}

	class BonWriter
	{
		public String outStr;
		bool doFormatting;
		
		FormatHelper f;
		int objDepth, arrDepth;

		[Inline]
		public this(String str, bool formatting = false)
		{
			outStr = str;
			doFormatting = formatting;
		}

		public ArrayBlockEnd StartArray()
		{
			if (doFormatting)
				f.DoTabs(outStr);
			outStr.Append('[');
			if (doFormatting)
			{
				f.NewLine(outStr);
				f.TabPush();
			}

			arrDepth++;

			return .(this);
		}

		public void EndArray()
		{
			Debug.Assert(arrDepth > 0);
			arrDepth--;

			if (doFormatting)
			{
				if (outStr.EndsWith(",\n"))
					outStr..RemoveFromEnd(2).Append('\n');

				f.TabPop();
				f.DoTabs(outStr);
			}
			else if (outStr.EndsWith(','))
				outStr.RemoveFromEnd(1);

			outStr.Append(']');
		}

		public ObjectBlockEnd StartObject()
		{
			if (doFormatting)
				f.DoTabs(outStr);
			outStr.Append('{');
			if (doFormatting)
			{
				f.NewLine(outStr);
				f.TabPush();
			}

			objDepth++;

			return .(this);
		}

		public void EndObject()
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
		
		public void EndEntry(bool doOneLine = false)
		{
			outStr.Append(',');
			if (doFormatting && !doOneLine)
				f.NewLine(outStr);
		}

		public void Identifier(StringView identifier)
		{
			Debug.Assert(outStr[outStr.Length - 1] != '=' && outStr[outStr.Length - 1] != ':');

			if (doFormatting)
				f.DoTabs(outStr);
			outStr..Append(identifier)
				.Append('=');
		}

		public void Key(StringView key)
		{
			Debug.Assert(outStr[outStr.Length - 1] != '=' && outStr[outStr.Length - 1] != ':');

			if (doFormatting)
				f.DoTabs(outStr);
			outStr..Append(key)
				.Append(':');
		}

		public void End()
		{
			Debug.Assert(objDepth == 0 && arrDepth == 0);

			if (outStr.Length > 0)
			{
				// Remove trailing newline with tabs (possibly)
				while (outStr[outStr.Length - 1].IsWhiteSpace)
					outStr.RemoveFromEnd(1);

				if (outStr[outStr.Length - 1] == ',')
					outStr.RemoveFromEnd(1);
			}
		}
	}
}
