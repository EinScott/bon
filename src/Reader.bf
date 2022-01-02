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
			UnterminatedComment = 1
		}
		public Errors errors;

		[Inline]
		public this(StringView str)
		{
			Debug.Assert(str.Ptr != null);

			inStr = str;

			EatEmpty();
		}

		void EatEmpty()
		{
			// Skip space, line breaks, tabs and comments
			var i = 0;
			var commentDepth = 0;
			let len = inStr.Length; // Since it won't be change in the following loop...
			for (; i < len; i++)
			{
				let char = inStr[[Unchecked]i];
				if (!char.IsWhiteSpace)
				{
					if (i + 1 < len)
					{
						if (char == '/' && inStr[[Unchecked]i + 1] == '*')
						{
							commentDepth++;
							i++;
							continue;
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

		public StringView Identifier()
		{
			// get identifier

			// consume =

			return ""; // temp
		}

		public void Expect(char8 token)
		{

		}

		public ArrayBlockEnd ArrayBlock()
		{
			return .(this);
		}

		public ObjectBlockEnd ObjectBlock()
		{
			return .(this);
		}
		
		void ArrayBlockEnd()
		{

		}

		void ObjectBlockEnd()
		{

		}

		public void EntryEnd()
		{

		}
	}
}