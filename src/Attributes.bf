using System;

namespace Bon
{
	// Putting this attribute on thing is theoretically not required if reflection
	// info is force included some other way (other attribute or build settings).
	// This makes it easier to work with types from other libraries (where you can
	// only retroactively force reflection in the build settings)
	[AttributeUsage(.Class|.Struct|.Enum, .AlwaysIncludeTarget, ReflectUser = .NonStaticFields | .DefaultConstructor, AlwaysIncludeUser = .AssumeInstantiated)]
	struct BonTargetAttribute : Attribute {}

	// In order to deserialize polymorphed values, the original type needs to be looked up by type name from bon string,
	// so we need some sort of central lookup for them. That's why they need to be specifically registered with this.
	// For inaccessible library types, you can just manually call gBonEnv.RegisterPolyType!(type) for it somewhere.
	[AttributeUsage(.Class|.Struct|.Enum)]
	struct BonPolyRegisterAttribute : Attribute, IComptimeTypeApply
	{
		[Comptime]
		public void ApplyToType(Type type)
		{
			Compiler.EmitTypeBody(type, "static this { gBonEnv.RegisterPolyType!(typeof(Self)); }");
		}
	}

	/// Forbid access to this field in (de-) serialization.
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct BonIgnoreAttribute : Attribute {}

	/// Allow access to this field in (de-) serialization! (essentially makes this act like any other field included as per bonEnv,
	/// so this will still not be serialized when the value is default and serializeFlags doesn't explicitly include defaults)
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct BonIncludeAttribute : Attribute {}
}