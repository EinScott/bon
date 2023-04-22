using System;
using System.Collections;
using Bon.Integrated;

namespace Bon
{
	[StaticInitPriority(90)]
	static
	{
		internal static void SetupBuiltinTypeHandlers(BonEnvironment env)
		{
			env.typeHandlers.Add(typeof(String), ((.)new => StringSerialize, (.)new => StringDeserialize));
			env.typeHandlers.Add(typeof(List<>), ((.)new => ListSerialize, (.)new => ListDeserialize));
			env.typeHandlers.Add(typeof(Dictionary<,>), ((.)new => DictionarySerialize, (.)new => DictionaryDeserialize));
			env.typeHandlers.Add(typeof(Nullable<>), ((.)new => NullableSerialize, (.)new => NullableDeserialize));
		}

		public static BonEnvironment gBonEnv = new .() ~ delete _;
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

	[Reflect(.NonStaticFields)]
	extension Array {}

	[BonTarget]
	extension Array1<T> {}

	[BonTarget]
	extension Array2<T> {}

	[BonTarget]
	extension Array3<T> {}

	[BonTarget]
	extension Array4<T> {}

	[BonTarget]
	extension Nullable<T> {}

	namespace Collections
	{
		// EnsureCapacity is forced to be included & reflected through build settings.
		[BonTarget]
		extension List<T> {}

		// TryAdd and Remove are forced to be included & reflected through build settings.
		[BonTarget]
		extension Dictionary<TKey,TValue>
		{
			[Reflect(.NonStaticFields)]
			extension Entry {}
		}
	}
}
#endif
