using System;
using System.Diagnostics;
using System.IO;
using System.Collections;
using Bon.Integrated;

namespace Bon
{
	// integrated serialize / deserialize
	// - demo with scene stuff?

	// TODO: & as a general token for retrieving references... maybe must be enabled with flag YAH- would be a serialize AND deserialize flag though
	// - deserial: put refs into list (current path + given relative ? + target variant), resolve path and handle at end

	// TODO: something like... @property = dd to call the property setter for deserialize? maybe?

	static class Bon
	{
#if BON_PROVIDE_ERROR
		internal static System.Threading.Monitor errMonitor = new .() ~ delete _;
		public static String LastDeserializeError = new .() ~ delete _;
#endif

		public static void Serialize<T>(T value, String into, BonEnvironment env = gBonEnv)
		{
			let writer = scope BonWriter(into, env.serializeFlags.HasFlag(.Verbose));
			var value;
			var variant = ValueView(typeof(T), &value);

			Serialize.Entry(writer, ref variant, env);
		}

		public static Result<BonContext> Deserialize<T>(ref T value, BonContext from, BonEnvironment env = gBonEnv)
		{
			let reader = scope BonReader();
			Try!(reader.Setup(from));
			var variant = ValueView(typeof(T), &value);

			return Deserialize.Entry(reader, ref variant, env);
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
