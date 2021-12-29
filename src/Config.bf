using System;

namespace Bon
{
	static class BonConfig
	{
		public static delegate void(StringView message) logOut ~ if (_ != null) delete _;
	}
}