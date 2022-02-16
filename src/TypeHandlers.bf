using System;
using System.Reflection;
using System.Diagnostics;
using System.Collections;

namespace Bon.Integrated
{
	static
	{
		public static void StringSerialize(BonWriter writer, ValueView val, BonEnvironment env, Serialize.ReferenceLookup refLook)
		{
			let str = *(String*)val.dataPtr;
			writer.String(str);
		}

		public static Result<void> StringDeserialize(BonReader reader, ValueView val, BonEnvironment env)
		{
			var str = *(String*)val.dataPtr;

			str.Clear();
			Deserialize.String!(reader, ref str, env);
			return .Ok;
		}

		public static void ListSerialize(BonWriter writer, ValueView val, BonEnvironment env, Serialize.ReferenceLookup refLook)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));
			Debug.Assert(t.GetField("mSize") case .Ok, Serialize.CompNoReflectionError!("List<>", "List<T>"));

			let arrType = t.GetGenericArg(0);
			var arrPtr = *(void**)GetValFieldPtr!(val, "mItems"); // *(T**)
			var count = GetValField!<int_cosize>(val, "mSize");

			if (count != 0 && !Serialize.IsArrayFilled(arrType, arrPtr, count, env))
				writer.Sizer((.)count);
			Serialize.Array(writer, arrType, arrPtr, count, env, refLook);
		}

		public static Result<void> ListDeserialize(BonReader reader, ValueView val, BonEnvironment env)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));

			int64 count = 0;
			if (reader.ArrayHasSizer())
			{
				let sizer = Try!(reader.ArraySizer<1>(false));
				count = Try!(Deserialize.ParseInt<int_cosize>(reader, sizer[0]));
			}
			else count = (.)Try!(reader.ArrayPeekCount());

			if (t.GetField("mSize") case .Err)
				Deserialize.Error!("No reflection data for type!", null, t);
			let currCount = GetValField!<int_cosize>(val, "mSize");
			
			let arrType = t.GetGenericArg(0);
			let itemsFieldPtr = GetValFieldPtr!(val, "mItems");

			if (currCount > count)
			{
				// The error handling here.. is a bit hacky..
				if (Deserialize.DefaultArray(reader, arrType, *(uint8**)itemsFieldPtr + count * arrType.Stride, currCount - count, env) case .Err)
					Deserialize.Error!("Couldn't shrink List (linked with previous error). Values in the back of the list that were to be defaulted likely couldn't be handled.", null, t);
			}
			else if (currCount < count)
			{
				if (((t.GetMethod("EnsureCapacity", .NonPublic|.Instance) case .Ok(let method))
					// Keep in mind, strictly speaking val.DataPtr is pointing to the field which references this list!
					&& method.Invoke(*(Object*)val.dataPtr, (int)count, true) case .Ok)) // returns T*, which is sizeof(int), so Variant doesnt alloc
				{
					// Null the new chunk
					Internal.MemSet(*(uint8**)itemsFieldPtr + currCount * arrType.Stride, 0, (count - currCount) * arrType.Stride);
				}
				else Deserialize.Error!("Method reflection data needed to enlargen List<> size. Include with [Reflect(.Methods)] extension List<T> {} or in build settings", null, t);
			}
			
			SetValField!<int_cosize>(val, "mSize", (int_cosize)count);

			// Since mItems is a pointer...
			let arrPtr = *(void**)itemsFieldPtr;
			Try!(Deserialize.Array(reader, arrType, arrPtr, count, env));

			return .Ok;
		}

		// TODO: we could do this for ICollection, but on ICollection
		// we'd have to call... Add... and also deserialize ever element
		// outselves before... which is kind of weird?
		// SerializeCollection<T>(..) where T : ICollection
		// demo with SizedList<> or something!

		// support Variant ... Guid,Version and some other useful stuff?
		// - for the last two, can we use a generic template that relies on ToString and Parse ?
		// handle type? we have polyType info...?

		// "!somethingName" are a way to make the deserializer call a function with this string as the key (also member type, type member is on), which then is expected to provide a variant to put there!
		// this could be a templated handler that calls a function? i guess... would do the parsing & being called in the first place part automatically then?
		// -> for example, for types like Asset<> registered, then can retrieve asset with name
	}
}