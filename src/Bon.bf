using System;
using System.IO;
using Bon.Integrated;

namespace Bon
{
	// integrated serialize / deserialize
	// - demo with scene stuff?

	// "&somethingName" example use
	// -> for example, for types like Asset<> registered, then can retrieve asset with name

	// TODO: something like... @property = dd to call the property setter in deserialize? maybe?
	// TODO: explain errors on how do i?, shorten their messages here. also document unused symbols that may be used like & and :

	static class Bon
	{
#if BON_PROVIDE_ERROR_MESSAGE
		static System.Threading.Monitor errLock = new .() ~ delete _;
		public static Event<delegate void(StringView errorMessage)> onDeserializeError = .() ~ _.Dispose();
#endif

		public static void Serialize<T>(T value, String into, BonEnvironment env = gBonEnv)
		{
			let writer = scope BonWriter(into, env.serializeFlags.HasFlag(.Verbose));
			var value;

			Serialize.Entry(writer, ValueView(typeof(T), &value), env);
		}

		public static Result<BonContext> Deserialize<T>(ref T value, BonContext from, BonEnvironment env = gBonEnv)
		{
			let reader = scope BonReader();
			Try!(reader.Setup(from));

			return Deserialize.Entry(reader, ValueView(typeof(T), &value), env);
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
