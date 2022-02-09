using System;
using System.Reflection;
using System.Diagnostics;
using System.Collections;

namespace Bon.Integrated
{
	static
	{
		public static void SerializeList(BonWriter writer, ref ValueView val, Serialize.ReferenceLookup refLook, BonEnvironment env)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));
			Debug.Assert(t.GetField("mSize") case .Ok, Serialize.CompNoReflectionError("List<>", "List<T>"));

			let arrType = t.GetGenericArg(0);
			var arrPtr = *(void**)GetValFieldPtr!(val, "mItems"); // *(T**)
			let count = GetValField!<int_cosize>(val, "mSize");

			// TODO: sizer only if last element is default (also for alloc arrays)
			writer.Sizer((uint64)count);
			Serialize.Array(writer, arrType, arrPtr, count, refLook, env);
		}

		public static Result<void> DeserializeList(BonReader reader, ref ValueView val, BonEnvironment env)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));

			int_cosize count = 0;
			if (reader.ArrayHasSizer())
			{
				let sizer = Try!(reader.ArraySizer<const 1>(false));
				count = Try!(Deserialize.ParseInt<int_cosize>(reader, sizer[0]));
			}
			else count = (.)Try!(reader.ArrayPeekCount());

			if (t.GetField("mSize") case .Err)
				Deserialize.Error!(t, "No reflection data forced for type!");
			let currCount = GetValField!<int_cosize>(val, "mSize");
			
			let arrType = t.GetGenericArg(0);
			let itemsFieldPtr = GetValFieldPtr!(val, "mItems");

			if (currCount > count)
			{
				// TODO: call defaultArray on the vals we exclude here!
			}
			else if (currCount < count)
			{
				if (((t.GetMethod("EnsureCapacity", .NonPublic|.Instance) case .Ok(let method))
					// Keep in mind, strictly speaking val.DataPtr is pointing to the field which references this list!
					&& method.Invoke(*(Object*)val.dataPtr, (int)count, true) case .Ok)) // returns T*, which is sizeof(int), so Variant doesnt alloc
				{
					if (arrType.IsObject)
					{
						// Null the new chunk, else we think this random data are valid pointers
						Internal.MemSet(*(uint8**)itemsFieldPtr + currCount * arrType.Stride, 0, (count - currCount) * arrType.Stride, arrType.Align);
					}
				}
				else Deserialize.Error!(t, "Method reflection data needed to enlargen List<> size"); // include with [Reflect(.Methods)] extension List<T> {} or in build settings
			}
			
			SetValField!<int_cosize>(val, "mSize", count);

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

		// "!somethingName" are a way to make the deserializer call a function with this string as the key (also member type, type member is on), which then is expected to provide a variant to put there!
		// this could be a templated handler that calls a function? i guess... would do the parsing & being called in the first place part automatically then?
		// -> for example, for types like Asset<> registered, then can retrieve asset with name
	}
}