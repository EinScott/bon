using System;
using Bon.Integrated;

using internal Bon;

namespace Bon
{
	struct BonContext
	{
		internal StringView strLeft;
		internal StringView origStr;
		internal bool hasMore;

		public int64 GetEntryCount(bool countLeft = true)
		{
			let reader = scope BonReader();
			if (reader.Setup(.(origStr, countLeft ? strLeft : origStr)) case .Err)
				return 0;
			return reader.FileEntryPeekCount();
		}

		public Result<BonContext> SkipEntry(int entryCount = 1)
		{
			let reader = scope BonReader();
			Try!(reader.Setup(this));
			Try!(reader.FileEntrySkip(entryCount));
			return .Ok(.(origStr, reader.inStr));
		}

		[Inline]
		public BonContext Rewind() => .(origStr);

		[Inline]
		public this(StringView bonString)
		{
			strLeft = origStr = bonString;
			hasMore = bonString.Length > 0;
		}

		[Inline]
		internal this(StringView origStr, StringView strLeft)
		{
			this.origStr = origStr;
			this.strLeft = strLeft;
			hasMore = strLeft.Length > 0;
		}

		[Inline]
		public static implicit operator Self(StringView s) => Self(s);
		[Inline]
		public static implicit operator Self(String s) => Self(s);
	}
}