using System;
using System.Diagnostics;
using System.IO;
using System.Collections;
using Bon.Integrated;

namespace Bon
{
	// integrated serialize / deserialize
	// near-arbitrary tree acces through helper methods derived from arbitrary parsing?
	//  generic templates for custom handlers...
	//  support Variant serialize?

	// GUIDES ON:
	// how to set up structures (what the lib expects, esp for allocation, ownership)
	// -> thing has to manage itself, do "if(_!=null)delete _;" if you really need to. Lists need to expect to delete their contents dynamically depending on use case, bon just allocates, you have to bother
	// how to force reflection data in the IDE (for example when the need for corlib types, such as Hash arises)
	// -> actually maybe special case the hashes, but still; do we make speical cases out of all non-prims? HOW DO WE EVEN HANDLE THESE, THEY SHOULDN'T BE GLOBAL? THEY ARE.. BUT
	// 		-> BONENVIRONMENT OBJECT -> has seperate list of handlers, takes static defaults, but ones can be added individually! YUP
	//		-> also put things like custom allocator and "oh a reference to this is wanted here" in there!

	// REFERENCES "&somethingName" are a way to make the deserializer call a function with this string as the key (also member type, type member is on), which then is expected to provide a variant to put there!

	// TODO: rethink syntax & tokens!

	static class Bon
	{
		public static void Serialize<T>(T value, String into, BonEnvironment env = gBonEnv)
		{
			let writer = scope BonWriter(into, env.serializeFlags.HasFlag(.Verbose));
			var value;
			var variant = Variant.CreateReference(typeof(T), &value);

			Serialize.Thing(writer, ref variant, env);
		}

		public static Result<void> Deserialize<T>(ref T value, StringView from, BonEnvironment env = gBonEnv)
		{
			let reader = scope BonReader(from);
			var variant = Variant.CreateReference(typeof(T), &value);

			return Deserialize.Thing(reader, ref variant, env);
		}
	}
}
