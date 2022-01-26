using System;
using System.Collections;
using System.Reflection;
using Bon.Integrated;
using System.Diagnostics;

namespace Bon
{
	enum BonSerializeFlags : uint8
	{
		/// Include public fields, don't include default fields, respect attributes (default)
		case Default = 0;

		/// Include private fields
		case AllowNonPublic = 1;

		/// Whether or not to include fields default values (e.g. null, etc)
		case IncludeDefault = 1 << 1;

		/// Ignore field attributes (only recommended for debugging / complete structure dumping)
		case IgnoreAttributes = 1 << 2;

		/// The produced string will be formatted (and slightly more verbose) for manual editing.
		case Verbose = 1 << 3;
	}

	enum BonDeserializeFlags : uint8
	{
		/// Fully set the state of the target structure based on the given string.
		case Default = 0;

		/// Values not mentioned in the given string will be left as they are
		/// instead of being nulled (and possibly deleted).
		case IgnoreUnmentionedValues = 1;
	}

	/// Defines the behavior of bon. May be modified globally (gBonEnv)
	/// or for some calls only be creating a BonEnvironment to modify
	/// and passing that to calls for use instead of the global fallback.
	class BonEnvironment
	{
		public BonSerializeFlags serializeFlags;
		public BonDeserializeFlags deserializeFlags;

		// TODO: put these into practise, iterate a bit, maybe write helper methods / mixins!
		public function void MakeThing(Variant refIntoVal);
		public function void DestroyThing(Variant valRef);

		// TODO
		// For custom handler registration
		// -> handler for custom serialize & deserialize
		// -> question then is, how much do we just convert to that format then?

		/// When bon needs to allocate or deallocate a reference type, a handler is called for it when possible
		/// instead of allocating with new or deleting. This can be used to gain more control over the allocation
		/// or specific types, for example to reference existing ones or register allocated instances elsewhere
		/// as well.
		/// BON WILL CALL THESE INSTEAD OF ALLOCATING/DEALLOCATING AND TRUSTS THE USER TO MANAGE IT.
		public Dictionary<Type, (MakeThing make, DestroyThing destroy)> instanceHandlers = new .() ~ delete _;

		/// Will be called for every deserialized StringView string. Must return a valid string view
		/// of the passed-in string.
		public function StringView(StringView view) stringViewHandler;

		/// Collection of registered types used in polymorphism.
		/// Required to get a type info from a serialized name.
		public Dictionary<String, Type> polyTypes = new .() ~ delete _;

		public mixin RegisterPolyType(Type type)
		{
			Debug.Assert(type is TypeInstance, "Type not set up properly! Put [Serializable,PolySerialize] on it or force reflection info & always include.");
			polyTypes.Add(((TypeInstance)type).[Friend]mName, type);
		}

		public this()
		{
			if (gBonEnv != null)
			{
				serializeFlags = gBonEnv.serializeFlags;
				deserializeFlags = gBonEnv.deserializeFlags;
				for (let pair in gBonEnv.instanceHandlers)
					instanceHandlers.Add(pair);
			}
		}
	}

	static
	{
		public static BonEnvironment gBonEnv =
			{
				let env = new BonEnvironment();

				env
			} ~ delete _;
	}
}