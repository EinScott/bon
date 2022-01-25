using System;

namespace Bon
{
	struct BonContext
	{
		internal StringView strLeft;
		internal StringView origStr;
		internal bool hasMore;

		// TODO maybe provide options to index the file level or skip stuff?
		// maybe this is easily doable with stuff from above, otherwise nah?

		[Inline]
		public this(StringView bonString)
		{
			strLeft = origStr = bonString;
			hasMore = bonString.Length > 0;
		}

		[Inline]
		public static implicit operator Self(StringView s) => Self(s);
		[Inline]
		public static implicit operator Self(String s) => Self(s);
	}
}