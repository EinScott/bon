using System;
using System.Reflection;
using System.Diagnostics;
using System.Collections;

namespace Bon.Integrated
{
	static
	{
		public static void StringSerialize(BonWriter writer, ValueView val, BonEnvironment env, SerializeValueState state)
		{
			let str = *(String*)val.dataPtr;
			writer.String(str);
		}

		public static Result<void> StringDeserialize(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state)
		{
			var str = *(String*)val.dataPtr;

			str.Clear();
			Deserialize.String!(reader, ref str, env);
			return .Ok;
		}

		public static void ListSerialize(BonWriter writer, ValueView val, BonEnvironment env, SerializeValueState state)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));
			Debug.Assert(t.GetField("mSize") case .Ok, Serialize.CompNoReflectionError!("List<>", "List<T>"));

			let arrType = t.GetGenericArg(0);
			var arrPtr = *(void**)GetValFieldPtr!(val, "mItems"); // *(T**)
			var count = GetValField!<int_cosize>(val, "mSize");

			bool includeAllInArray = state.arrayKeepUnlessSet;
			if (count != 0 && !includeAllInArray && !Serialize.IsArrayFilled(arrType, arrPtr, count, env))
				writer.Sizer((.)count);
			Serialize.Array(writer, arrType, arrPtr, count, env, includeAllInArray);
		}

		public static Result<void> ListDeserialize(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state)
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

			if (currCount > count && !state.arrayKeepUnlessSet)
			{
				// The error handling here.. is a bit hacky..
				if (Deserialize.DefaultArray(reader, arrType, *(uint8**)itemsFieldPtr + count * arrType.Stride, currCount - count, env, true) case .Err)
					Deserialize.Error!("Couldn't shrink List (linked with previous error). Values in the back of the list that were to be removed likely couldn't be handled.", null, t);

				// Here we only set it if we ignore the unmentioned stuff
				SetValField!<int_cosize>(val, "mSize", (int_cosize)count);
			}
			else if (currCount < count)
			{
				if ((t.GetMethod("EnsureCapacity", .NonPublic|.Instance) case .Ok(let method))
					// Keep in mind, strictly speaking val.DataPtr is pointing to the field which references this list!
					&& method.Invoke(*(Object*)val.dataPtr, (int)count, true) case .Ok) // returns T*, which is sizeof(int), so Variant doesnt alloc
				{
					// Null the new chunk
					Internal.MemSet(*(uint8**)itemsFieldPtr + currCount * arrType.Stride, 0, (.)(count - currCount) * arrType.Stride);
				}
				else Deserialize.Error!("EnsureCapacity method needs to be included & reflected to enlargen List<> size", null, t);

				SetValField!<int_cosize>(val, "mSize", (int_cosize)count);
			}
			
			// Since mItems is a pointer...
			let arrPtr = *(void**)itemsFieldPtr;
			Try!(Deserialize.Array(reader, arrType, arrPtr, count, env, state.arrayKeepUnlessSet));

			return .Ok;
		}

		public static void DictionarySerialize(BonWriter writer, ValueView val, BonEnvironment env, SerializeValueState state)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(Dictionary<,>));
			Debug.Assert(t.GetField("mCount") case .Ok, Serialize.CompNoReflectionError!("Dictionary<,>", "Dictionary<T1,T2>"));

			let keyType = t.GetGenericArg(0);
			let valueType = t.GetGenericArg(1);
			var count = GetValField!<int_cosize>(val, "mCount");

			let classData = *(uint8**)val.dataPtr;
			let entriesField = val.type.GetField("mEntries").Get();
			var entriesPtr = *(uint8**)(classData + entriesField.[Inline]MemberOffset); // *(Entry**)
			let entryType = entriesField.[Inline]FieldType.UnderlyingType;
			let entryStride = entryType.Stride;
			int entryHashCodeOffset = -1, entryKeyOffset = -1, entryValueOffset = -1;
			for (let f in entryType.GetFields(.Instance))
			{
				switch (f.[Inline]Name)
				{
				case "mHashCode":
					entryHashCodeOffset = f.[Inline]MemberOffset;
				case "mKey":
					entryKeyOffset = f.[Inline]MemberOffset;
				case "mValue":
					entryValueOffset = f.[Inline]MemberOffset;
				}
			}
			Runtime.Assert(entryHashCodeOffset != -1 && entryKeyOffset != -1 && entryValueOffset != -1);

			using (writer.ArrayBlock())
			{
				int64 index = 0;
				int64 currentIndex = -1;

				ENTRIES:while (true)
				{
					MOVENEXT:do
					{
						// This is basically stolen from Dictionary.Enumerator.MoveNext()
						// -> go through the dict entries, break if we're done

						while ((uint)index < (uint)count)
						{
							// mEntries[mIndex].mHashCode
							if (*(int_cosize*)(entriesPtr + (index * entryStride) + entryHashCodeOffset) >= 0)
							{
								currentIndex = index;
								index++;
								break MOVENEXT;
							}
							index++;
						}

						break ENTRIES;
					}

					let keyVal = ValueView(keyType, entriesPtr + (currentIndex * entryStride) + entryKeyOffset);
					let valueVal = ValueView(valueType, entriesPtr + (currentIndex * entryStride) + entryValueOffset);

					Serialize.Value(writer, keyVal, env);
					writer.Pair();
					Serialize.Value(writer, valueVal, env);
				}
			}
		}

		public static Result<void> DictionaryDeserialize(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(Dictionary<,>));

			if (t.GetField("mCount") case .Err)
				Deserialize.Error!("No reflection data for type!", null, t);

			let keyType = t.GetGenericArg(0);
			let valueType = t.GetGenericArg(1);
			var count = GetValField!<int_cosize>(val, "mCount");

			let classData = *(uint8**)val.dataPtr;

			MethodInfo tryAdd = default;
			MethodInfo remove = default;
			for (let m in t.GetMethods(.Instance))
			{
				if (m.Name == "TryAdd"
					&& m.ParamCount == 3)
					tryAdd = m;
				else if (m.Name == "Remove"
					&& m.ParamCount == 1 && m.GetParamType(0) == keyType)
					remove = m;

				if (tryAdd.IsInitialized && remove.IsInitialized)
					break;
			}

			if (!tryAdd.IsInitialized || !remove.IsInitialized)
				Deserialize.Error!("TryAdd and Remove methods need to be included & reflected to deserialize Dictionary<,>", null, t);

			// Relative positions of entries stay the same regardless of realloc
			List<(int keyOffset, int valueOffset, bool found)> current = scope .(Math.Max(count, 16));

			let entriesField = t.GetField("mEntries").Get();
			var entriesFieldPtr = classData + entriesField.[Inline]MemberOffset; // Entry**

			if (count > 0)
			{
				// Copy from DictionarySerialize()... mostly

				let entriesPtr = *(uint8**)(entriesFieldPtr); // *(Entry**)
				let entryType = entriesField.[Inline]FieldType.UnderlyingType;
				let entryStride = entryType.Stride;
				int entryHashCodeOffset = -1, entryKeyOffset = -1, entryValueOffset = -1;
				for (let f in entryType.GetFields(.Instance))
				{
					switch (f.[Inline]Name)
					{
					case "mHashCode":
						entryHashCodeOffset = f.[Inline]MemberOffset;
					case "mKey":
						entryKeyOffset = f.[Inline]MemberOffset;
					case "mValue":
						entryValueOffset = f.[Inline]MemberOffset;
					}
				}
				Runtime.Assert(entryHashCodeOffset != -1 && entryKeyOffset != -1 && entryValueOffset != -1);

				int64 index = 0;
				int64 currentIndex = -1;

				ENTRIES:while (true)
				{
					MOVENEXT:do
					{
						// This is basically stolen from Dictionary.Enumerator.MoveNext()
						// -> go through the dict entries, break if we're done

						while ((uint)index < (uint)count)
						{
							// mEntries[mIndex].mHashCode
							if (*(int_cosize*)(entriesPtr + (index * entryStride) + entryHashCodeOffset) >= 0)
							{
								currentIndex = index;
								index++;
								break MOVENEXT;
							}
							index++;
						}

						break ENTRIES;
					}

					current.Add(((.)(currentIndex * entryStride) + entryKeyOffset, (.)(currentIndex * entryStride) + entryValueOffset, false));
				}
			}

			Try!(reader.ArrayBlock());

			ARRAY:while (reader.ArrayHasMore())
			{
				// We don't know where this goes yet... is this an
				// existing entry we can set the value of? or a new one?
				uint8[] keyData;
				if (keyType.Size < 1024)
					keyData = scope:ARRAY uint8[keyType.Size];
				else
				{
					keyData = new uint8[keyType.Size];
					defer:ARRAY delete keyData;
				}
				let keyVal = ValueView(keyType, &keyData[0]);

				Try!(Deserialize.Value(reader, keyVal, env));

				uint8* keyPtr = null, valuePtr = null;
				uint8** keyOutPtr = &keyPtr, valueOutPtr = &valuePtr;
				if (tryAdd.Invoke(.CreateReference(val.type, classData), keyVal.ToInvokeVariant(),
					.CreateReference(tryAdd.GetParamType(1), &keyOutPtr),
					.CreateReference(tryAdd.GetParamType(2), &valueOutPtr)) case .Ok(var boolRet))
				{
					let entriesPtr = *(uint8**)(entriesFieldPtr);

					for (var e in ref current)
					{
						if (keyPtr == entriesPtr + e.keyOffset)
						{
							if (!e.found)
							{
								e.found = true;
								break;
							}
							else Deserialize.Error!("Dictionary key was already added", reader, t);
						}
					}

					if (!*((bool*)boolRet.DataPtr))
					{
						// This is definitely not very ideal. But we cannot try to deserialize directly into
						// an existing key, because we only get it with the hash. So we need to try to clear
						// it here in case it's something we can't null.
						Try!(Deserialize.MakeDefault(reader, ValueView(keyType, keyPtr), env, true));

						// Copy key data into there just in case (maybe not everything affects the hash)
						Internal.MemCpy(keyPtr, &keyData[0], keyData.Count);
					}
					else current.Add((keyPtr - entriesPtr, valuePtr - entriesPtr, true));
				}
				else Deserialize.Error!("Failed to invoke TryAdd on Dictionary<,>!", null, t);

				let valueVal = ValueView(valueType, valuePtr);
				Try!(reader.Pair());
				Try!(Deserialize.Value(reader, valueVal, env));

				if (reader.ArrayHasMore())
					Try!(reader.EntryEnd());
			}

			Try!(reader.ArrayBlockEnd());

			if (!state.arrayKeepUnlessSet)
			{
				for (let e in current)
				{
					if (!e.found)
					{
						let entriesPtr = *(uint8**)(entriesFieldPtr);
						
						let keyVal = ValueView(keyType, entriesPtr + e.keyOffset);
						let checkKeyDefaultRes = Deserialize.CheckCanDefault(reader, keyVal, env, true);
						if (checkKeyDefaultRes case .Err || Deserialize.MakeDefault(reader, ValueView(valueType, entriesPtr + e.valueOffset), env, true) case .Err)
							Deserialize.Error!("Couldn't shrink Dictionary (linked with previous error). Unmentioned pairs that were to be removed from the dictioanry likely couldn't be handled.", null, t);

						if (remove.Invoke(.CreateReference(val.type, classData), keyVal.ToInvokeVariant()) case .Ok(var boolRet))
							Debug.Assert(*((bool*)boolRet.DataPtr));
						else Deserialize.Error!("Failed to invoke Remove on Dictionary<,>!", null, t);

						Deserialize.MakeDefaultUnchecked(reader, keyVal, env, true, checkKeyDefaultRes.Get());
					}
				}
			}

			return .Ok;
		}

		public static void NullableSerialize(BonWriter writer, ValueView val, BonEnvironment env, SerializeValueState state)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(Nullable<>));
			Debug.Assert(t.GetField("mValue") case .Ok, Serialize.CompNoReflectionError!("Nullable<>", "Nullable<T>"));

			if (!GetValField!<bool>(val, "mHasValue"))
				writer.Null();
			else
			{
				let valType = t.GetGenericArg(0);
				let structPtr = GetValFieldPtr!(val, "mValue");
				Serialize.Value(writer, ValueView(valType, structPtr), env);
			}
		}

		public static Result<void> NullableDeserialize(BonReader reader, ValueView val, BonEnvironment env, DeserializeValueState state)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(Nullable<>));

			if (t.GetField("mValue") case .Err)
				Deserialize.Error!("No reflection data for type!", null, t);

			let valType = t.GetGenericArg(0);
			let structPtr = GetValFieldPtr!(val, "mValue");
			let hasValPtr = GetValFieldPtr!(val, "mHasValue");
			let structVal = ValueView(valType, structPtr);

			if (reader.IsNull())
			{
				*(bool*)hasValPtr = false;
				Try!(Deserialize.MakeDefault(reader, structVal, env, true));

				Try!(reader.ConsumeEmpty());
			}
			else
			{
				*(bool*)hasValPtr = true;
				Try!(Deserialize.Value(reader, structVal, env));
			}

			return .Ok;
		}

		// We *could* add handlers for stuff like Guid, Version, Type, Sha256, md5,... here
	}
}