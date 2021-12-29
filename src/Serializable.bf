using System;

namespace Bon
{
	// Putting this attribute on thing is theoretically not required if reflection
	// info is force included some other way (other attribute or build settings).
	// This makes it easier to work with types from other libraries (where you can
	// only retroactively force reflection in the build settings)
	[AttributeUsage(.Class|.Struct|.Enum, .AlwaysIncludeTarget | .ReflectAttribute, ReflectUser = .AllMembers, AlwaysIncludeUser = .IncludeAllMethods | .AssumeInstantiated)]
	struct SerializableAttribute : Attribute {}

	/// Never serialize this field!
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct NoSerializeAttribute : Attribute {}

	/// Always serialize this field! (essentially makes this act like any other field included as per includeFlags,
	/// so this will still not be serialized when the value is default and includeFlags doesn't explicitly include defaults)
	[AttributeUsage(.Field, .ReflectAttribute)]
	struct DoSerializeAttribute : Attribute {}
}