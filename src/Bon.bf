using System;
using System.Diagnostics;
using System.IO;
using Bon.Integrated;

namespace Bon
{
	// other syntax
	// integrated serialize / deserialize
	// -> implemented arbitrary type array (thats the custom part) of structs
	// more helpers ?
	// custom serialize handlers by type?
	// near-arbitrary tree acces through helper methods derived from arbitrary parsing?

	// GUIDES ON:
	// how to set up structures (what the lib expects, esp for allocation, ownership)
	// how to force reflection data in the IDE (for example when the need for corlib types, such as Hash arises)
	// -> actually maybe special case the hashes, but still; do we make speical cases out of all non-prims? HOW DO WE EVEN HANDLE THESE, THEY SHOULDN'T BE GLOBAL?
	// 		-> BONENVIRONMENT OBJECT -> has seperate list of handlers, takes static defaults, but ones can be added individually!

	static class Bon
	{
		public static void Serialize<T>(T value, String into, BonSerializeFlags flags = .DefaultFlags) where T : struct
		{
			let writer = scope BonWriter(into, flags.HasFlag(.Verbose));
			var value;
			var variant = Variant.CreateReference(typeof(T), &value);
			Serialize.Thing(writer, ref variant, flags);
			writer.End();
		}

		public static Result<void> Deserialize<T>(T into, StringView from) where T : class
		{
			return .Ok;
		}

		public static Result<void> Deserialize<T>(ref T into, StringView from) where T : struct
		{

			return .Ok;
		}

		public static Result<T> Deserialize<T>(StringView from)
		{
			return .Ok(default);
		}

		// UPDATE: I'm since convinced this is a bad idea! We should just document how to properly setup types!
		// Value would combine the things thats deserialized with List<Object>, that keeps all the
		// refs for new types created, for example strings for stringViews...
		// there should be alternatives to this but this seems easy for when you just want to
		// poke at some data structure
		/*public static Result<void> Deserialize<T>(BonValue<T> into, StringView from)
		{

		}*/
	}
}
