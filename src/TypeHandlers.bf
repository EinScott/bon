using System;
using System.Reflection;
using System.Diagnostics;
using System.Collections;

namespace Bon.Integrated
{
	static
	{
		public static void StringSerialize(BonWriter writer, ValueView val, BonEnvironment env)
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

		public static void ListSerialize(BonWriter writer, ValueView val, BonEnvironment env)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(List<>));
			Debug.Assert(t.GetField("mSize") case .Ok, Serialize.CompNoReflectionError!("List<>", "List<T>"));

			let arrType = t.GetGenericArg(0);
			var arrPtr = *(void**)GetValFieldPtr!(val, "mItems"); // *(T**)
			var count = GetValField!<int_cosize>(val, "mSize");

			if (count != 0 && !Serialize.IsArrayFilled(arrType, arrPtr, count, env))
				writer.Sizer((.)count);
			Serialize.Array(writer, arrType, arrPtr, count, env);
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
				if ((t.GetMethod("EnsureCapacity", .NonPublic|.Instance) case .Ok(let method))
					// Keep in mind, strictly speaking val.DataPtr is pointing to the field which references this list!
					&& method.Invoke(*(Object*)val.dataPtr, (int)count, true) case .Ok) // returns T*, which is sizeof(int), so Variant doesnt alloc
				{
					// Null the new chunk
					Internal.MemSet(*(uint8**)itemsFieldPtr + currCount * arrType.Stride, 0, (count - currCount) * arrType.Stride);
				}
				else Deserialize.Error!("EnsureCapacity method needs to be included & reflected to enlargen List<> size", null, t);
			}
			
			SetValField!<int_cosize>(val, "mSize", (int_cosize)count);

			// Since mItems is a pointer...
			let arrPtr = *(void**)itemsFieldPtr;
			Try!(Deserialize.Array(reader, arrType, arrPtr, count, env));

			return .Ok;
		}

		public static void DictionarySerialize(BonWriter writer, ValueView val, BonEnvironment env)
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
			let entryHashCodeOffset = entryType.GetField("mHashCode").Get().[Inline]MemberOffset;
			let entryKeyOffset = entryType.GetField("mKey").Get().[Inline]MemberOffset;
			let entryValueOffset = entryType.GetField("mValue").Get().[Inline]MemberOffset;

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

		public static Result<void> DictionaryDeserialize(BonReader reader, ValueView val, BonEnvironment env)
		{
			let t = (SpecializedGenericType)val.type;

			Debug.Assert(t.UnspecializedType == typeof(Dictionary<,>));

			if (t.GetField("mCount") case .Err)
				Deserialize.Error!("No reflection data for type!", null, t);

			let keyType = t.GetGenericArg(0);
			let valueType = t.GetGenericArg(1);
			var count = GetValField!<int_cosize>(val, "mCount");

			let classData = *(uint8**)val.dataPtr;
			let entriesField = t.GetField("mEntries").Get();
			var entriesPtr = *(uint8**)(classData + entriesField.[Inline]MemberOffset); // *(Entry**)
			let entryType = entriesField.[Inline]FieldType.UnderlyingType;
			let entryStride = entryType.Stride;
			let entryHashCodeOffset = entryType.GetField("mHashCode").Get().[Inline]MemberOffset;
			let entryKeyOffset = entryType.GetField("mKey").Get().[Inline]MemberOffset;
			let entryValueOffset = entryType.GetField("mValue").Get().[Inline]MemberOffset;

			MethodInfo tryAdd = default;
			for (let m in t.GetMethods(.Instance))
			{
				if (m.Name == "TryAdd"
					&& m.ParamCount == 3)
				{
					tryAdd = m;
					break;
				}
			}

			if (tryAdd == default)
				Deserialize.Error!("TryAdd method needs to be included & reflected to deserialize Dictionary<,>", null, t);

			List<(ValueView keyVal, ValueView valueVal, bool found)> current = null;

			// get current dict cases to look up from
			if (count > 0)
			{
				current = scope:: .(count);

				// Copy from DictionarySerialize()

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

					current.Add((keyVal, valueVal, false));
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
				Try!(reader.Pair());

				// TODO: sicne this passes... the error with mBuckets not being null in dict must be a bug in Invoke!!
				Debug.Assert(*(int_cosize**)(classData + t.GetField("mBuckets").Get().MemberOffset) == null);
				Debug.Assert(*(int_cosize**)((*(uint8**)val.ToVariantRefence().DataPtr) + t.GetField("mBuckets").Get().MemberOffset) == null);

				uint8* keyPtr, valuePtr;
				uint8** keyOutPtr = &keyPtr, valueOutPtr = &valuePtr;
				if (tryAdd.Invoke(val.ToVariantRefence(), keyVal.ToVariantRefence(),
					.CreateReference(tryAdd.GetParamType(1), &keyOutPtr),
					.CreateReference(tryAdd.GetParamType(2), &valueOutPtr)) case .Ok(var boolRet))
				{
					// !TypeHoldsObject!(keyType)

					Debug.FatalError();

					if (*((bool*)boolRet.DataPtr))
					{
						
					}
					else
					{

					}

					boolRet.Dispose();
				}
				else Deserialize.Error!("Failed to invoke TryAdd on Dictionary<,>!", null, t);

				// is that key already in the dictionary? OR if the value is something we just allocated, just go for it. We can't dealloc it anyways
				// -> get entry & store val loc
				// -> mark entry as added (should keep track of those as well to prevent duplicates?)
				// else
				// -> add new entry, store val loc

				//let valueVal = ValueView(valueType, valuePtr);
				Try!(Deserialize.Value(reader, keyVal, env));

				if (reader.ArrayHasMore())
					Try!(reader.EntryEnd());
			}

			Try!(reader.ArrayBlockEnd());

			// remove all current non-found entries (if that's possible)
			Debug.FatalError();

			return .Ok;
		}

		// We *could* add handlers for stuff like Guid, Version, Type, Sha256, md5,... here
	}
}