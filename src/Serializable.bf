using System;

namespace Bon
{
	// Putting this attribute on thing is theoretically not required if reflection
	// info is force included some other way (other attribute or build settings).
	// This makes it easier to work with types from other libraries (where you can
	// only retroactively force reflection in the build settings)
	[AttributeUsage(.Class|.Struct|.Enum, .AlwaysIncludeTarget, ReflectUser = .AllMembers | .DefaultConstructor, AlwaysIncludeUser = .IncludeAllMethods /* for default constructor */ | .AssumeInstantiated | .Type)]
	struct SerializableAttribute : Attribute {}

	// In order to deserialize polymorphed values, the original type needs to be looked up by type name from bon string,
	// so we need some sort of central lookup for them. That's why they need to be specifically registered with this.
	// For inaccessible library types, you can just manually call gBonEnv.RegisterPolyType!(type) for it somewhere.
	[AttributeUsage(.Class|.Struct|.Enum)]
	struct PolySerializeAttribute : Attribute, IComptimeTypeApply
	{
		[Comptime]
		public void ApplyToType(Type type)
		{
			Compiler.EmitTypeBody(type, "static this { gBonEnv.RegisterPolyType!(typeof(Self)); }");
		}
	}

	/// Never serialize this field!
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct NoSerializeAttribute : Attribute {}

	/// Always serialize this field! (essentially makes this act like any other field included as per includeFlags,
	/// so this will still not be serialized when the value is default and includeFlags doesn't explicitly include defaults)
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct DoSerializeAttribute : Attribute {}
}