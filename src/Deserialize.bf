using System;

namespace Bon.Integrated
{
	static class Deserialize
	{
		// verify identifier names!

		// flag to allow allocation of needed types, otherwise we WANT the classes to allocate their stuff when we call their constructor!!
		// -> theres a problem with this idea... the allocation of the initial object.. is it passed in?
		//    YES!! -> THEY ARE RESPONSIBLE. EVEN IF THE STRUCT DOESNT NEW THE CLASS, WE EITHER GET THE INSTANCE OR IGNORE THE THING!!

		// TODO: to deserialize stringView we probably want to include a callback? it could look up the string and return it, or allocate it somewhere!
	}
}