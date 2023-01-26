using System;
using System.Collections;
using System.Diagnostics;
using System.Reflection;
using Bon.Integrated;

using internal Bon;

namespace Bon
{
	enum BonSerializeFlags : uint8
	{
		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields (but not things we ignore!)
		case IncludeNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		/// Ignore field permission attributes (only recommended for debugging / complete structure dumping)
		case IgnorePermissions = 1 << 3 | IncludeNonPublic;

		/// The produced string will be formatted (and slightly more verbose) for manual editing.
		case Verbose = 1 << 4;
	}
	
	public delegate void MakeThingFunc(ValueView refIntoVal);

	public delegate void HandleSerializeFunc(BonWriter writer, ValueView val, BonEnvironment env, SerializeValueState state);
	public delegate Result<void> HandleDeserializeFunc(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state);

	/// Defines the behavior of bon.
	class BonEnvironment
	{
		public BonSerializeFlags serializeFlags;

		/// When bon serializes or deserializes an unknown type, it checks this to see if there are custom
		/// functions to handle this type. Functions can be registered by type or by unspecialized generic
		/// type, like List<>. For examples, see TypeHandlers.bf
		public Dictionary<Type, (HandleSerializeFunc serialize, HandleDeserializeFunc deserialize)> typeHandlers = new .() ~ {
			for (let pair in _)
			{
				delete pair.value.serialize;
				delete pair.value.deserialize;
			}
			delete _;
		}

		/// When bon needs to allocate a reference type, a handler is called for it when possible
		/// instead of allocating with new. This can be used to gain more control over the allocation
		/// or specific types, for example to reference existing ones or register allocated instances
		/// elsewhere as well.
		/// Functions can be registered by type or by unspecialized generic type, like List<> but keep in mind
		/// that you need to deal with any specialized type indicated by the ValueView.
		public Dictionary<Type, MakeThingFunc> allocHandlers = new .() ~ DeleteDictionaryAndValues!(_);

		/// Will be called for every deserialized StringView string. Must return a valid string view
		/// of the passed-in string.
		public delegate StringView(StringView view) stringViewHandler ~ if (_ != null) delete _;

		// Collection of registered types used in polymorphism.
		// Required to get a type info from a serialized name.
		Dictionary<String, Type> polyTypes = new .() ~ DeleteDictionaryAndKeys!(_);

		public mixin RegisterPolyType(Type type)
		{
			Debug.Assert(type is TypeInstance, "Type not set up properly! Put [BonTarget] on it or force reflection info & always include.");
			let str = type.GetFullName(.. new .(256));
			if (!polyTypes.ContainsKey(str))
				polyTypes.Add(str, type);
			else delete str;
		}

		[Inline]
		public bool TryGetPolyType(StringView typeName, out Type type)
		{
			return polyTypes.TryGetValue(scope .(typeName), out type);
		}

		public this()
		{
#if !BON_NO_DEFAULT_SETUP
			SetupBuiltinTypeHandlers(this);
#endif

			if (gBonEnv == null)
				return;

			// Copy poly type registration from global env
			for (let pair in gBonEnv.polyTypes)
				polyTypes.Add(new .(pair.key), pair.value);
		}
	}
}