using System;
using System.Collections;
using Bon.Integrated;

namespace Bon
{
	[StaticInitPriority(90)]
	static
	{
		static this()
		{
			let env = gBonEnv = new BonEnvironment();

#if !BON_NO_DEFAULT_SETUP
			env.RegisterPolyType!(typeof(Boolean));
			env.RegisterPolyType!(typeof(Int));
			env.RegisterPolyType!(typeof(Int64));
			env.RegisterPolyType!(typeof(Int32));
			env.RegisterPolyType!(typeof(Int16));
			env.RegisterPolyType!(typeof(Int8));
			env.RegisterPolyType!(typeof(UInt));
			env.RegisterPolyType!(typeof(UInt64));
			env.RegisterPolyType!(typeof(UInt32));
			env.RegisterPolyType!(typeof(UInt16));
			env.RegisterPolyType!(typeof(UInt8));
			env.RegisterPolyType!(typeof(Char8));
			env.RegisterPolyType!(typeof(Char16));
			env.RegisterPolyType!(typeof(Char32));
			env.RegisterPolyType!(typeof(Float));
			env.RegisterPolyType!(typeof(Double));

			env.serializeHandlers.Add(typeof(List<>), ((.)=> SerializeList, (.)=> DeserializeList));
#endif
		}

		public static BonEnvironment gBonEnv ~ delete _;
	}
}

#if !BON_NO_DEFAULT_SETUP
using Bon;

namespace System
{
	// Include some reflection data that we need to support
	// these builtin types!

	[BonTarget]
	extension String {}

	// We could, for example, put this in the static constructor
	// to automatically make them able to be used as poly types...
	// but that would be just wasteful. Still, if you need it
	// static this() => gBonEnv.RegisterPolyType!(typeof(Self));

	[Reflect(.AllMembers)]
	extension Array {}

	[BonTarget]
	extension Array1<T> {}

	[BonTarget]
	extension Array2<T> {}

	[BonTarget]
	extension Array3<T> {}

	[BonTarget]
	extension Array4<T> {}

	namespace Collections
	{
		// EnsureCapacity is forced to be included through build settings.
		[BonTarget,Reflect(.Methods)] // .Methods is needed to call EnsureCapacity
		extension List<T> {}
	}
}
#endif
