using System;
using System.Diagnostics;
using System.IO;
using System.Collections;
using Bon.Integrated;

namespace Bon
{
	// GUIDES ON:
	// examples / basic out of the box usage
	// how to set up structures (what the lib expects, esp for allocation, ownership)
	// -> all common errors or things that go wrong in usage "why it says reflection missing" "how to use polyTypes" "custom handlers?" "manage memory?"
	//  -> thing has to manage itself, do "if(_!=null)delete _;" if you really need to. Lists need to expect to delete their contents dynamically depending on use case, bon just allocates, you have to bother
	//  ->how to force reflection data in the IDE
	// integrated serialize / deserialize
	// - demo with scene stuff?

	// TODO: & as a general token for retrieving references... maybe must be enabled with flag YAH- would be a serialize AND deserialize flag though
	// - serial: see ptr comment (we'd need a lookup for that though)
	// - deserial: put into list (current path + given relative ?), resolve path and handle at end

	static class Bon
	{
		public static void Serialize<T>(T value, String into, BonEnvironment env = gBonEnv)
		{
			let writer = scope BonWriter(into, env.serializeFlags.HasFlag(.Verbose));
			var value;
			var variant = Variant.CreateReference(typeof(T), &value);

			Serialize.Thing(writer, ref variant, env);
		}

		public static Result<BonContext> Deserialize<T>(ref T value, BonContext from, BonEnvironment env = gBonEnv)
		{
			let reader = scope BonReader();
			Try!(reader.Setup(from));
			var variant = Variant.CreateReference(typeof(T), &value);

			return Deserialize.Thing(reader, ref variant, env);
		}

		public static Result<void> SerializeIntoFile<T>(T value, StringView path, BonEnvironment env = gBonEnv)
		{
			let str = Serialize(value, .. scope .(1024), env);
			return File.WriteAllText(path, str);
		}

		public static Result<void> DeserializeFromFile<T>(ref T value, StringView path, BonEnvironment env = gBonEnv)
		{
			let str = scope String(1024);
			Try!(File.ReadAllText(path, str, true));
			Try!(Deserialize(ref value, str, env));
			return .Ok;
		}
	}
}
