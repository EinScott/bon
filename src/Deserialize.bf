using System;
using System.Diagnostics;
using System.Reflection;

namespace Bon.Integrated
{
	static class Deserialize
	{
		// flag to allow allocation of needed types, otherwise we WANT the classes to allocate their stuff when we call their constructor!!
		// -> theres a problem with this idea... the allocation of the initial object.. is it passed in?
		//    YES!! -> THEY ARE RESPONSIBLE. EVEN IF THE STRUCT DOESNT NEW THE CLASS, WE EITHER GET THE INSTANCE OR IGNORE THE THING!!

		// TODO: to deserialize stringView we probably want to include a callback? it could look up the string and return it, or allocate it somewhere!

		[Inline]
		public static Result<void> Thing<T>(BonReader reader, ref T into)
		{
			if (reader.ReachedEnd())
				into = default;
			else
			{
				var variant = Variant.CreateReference(typeof(T), &into);
				Try!(Value(reader, ref variant));

				if (!reader.ReachedEnd())
					return .Err;
			}
			return .Ok;
		}

		public static Result<void> Value(BonReader reader, ref Variant val)
		{
			Type valType = val.VariantType;

			if (valType.IsPrimitive)
			{
				if (valType.IsInteger)
					Integer!(valType);
				else if (valType.IsFloatingPoint)
					Float!(valType);
				else if (valType.IsChar)
					Char!(valType);
				else if (valType == typeof(bool))
					Bool!();
				else Debug.FatalError(); // Should be unreachable
			}
			else if (valType.IsTypedPrimitive)
			{

			}
			else if (valType.IsStruct)
			{

			}
			else if (valType is SizedArrayType)
			{

			}
			else if (valType.IsObject)
			{

			}
			else if (valType.IsPointer)
			{
				Debug.FatalError(); // TODO
			}
			else Debug.FatalError();

			if (valType.IsInteger
				|| valType.IsTypedPrimitive && valType.UnderlyingType.IsInteger)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '-')
					numLen++;

				if (numLen == 0)
					LogErrorReturn!("Expected integer literal");

				switch (valType)
				{
				case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
					if (int64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, valType.Size);
					else LogErrorReturn!("Failed to parse integer");
				default: // unsigned
					if (uint64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, valType.Size);
					else LogErrorReturn!("Failed to parse integer");
				}

				buffer.RemoveFromStart(numLen);
			}
			else if (valType.IsFloatingPoint
				|| valType.IsTypedPrimitive && valType.UnderlyingType.IsFloatingPoint)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '.' || buffer[numLen] == '-' || buffer[numLen] == 'e')
					numLen++;

				if (numLen == 0)
					LogErrorReturn!("Expected floating point literal");

				switch (valType)
				{
				case typeof(float):
					if (float.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(float*)val.DataPtr = num;
					else LogErrorReturn!("Failed to parse floating point");
				case typeof(double):
					if (double.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(double*)val.DataPtr = num;
					else LogErrorReturn!("Failed to parse floating point");
				default:
					LogErrorReturn!("Unexpected floating point");
				}

				buffer.RemoveFromStart(numLen);
			}
			else if (valType == typeof(bool))
			{
				if (buffer.StartsWith(bool.TrueString, .OrdinalIgnoreCase))
				{
					*(bool*)val.DataPtr = true;
					buffer.RemoveFromStart(bool.TrueString.Length);
				}
				else if (buffer[0] == '1')
				{
					*(bool*)val.DataPtr = true;
					buffer.RemoveFromStart(1);
				}
				else if (buffer.StartsWith(bool.FalseString, .OrdinalIgnoreCase))
				{
					// Is already 0, sooOOo nothing to do here
					buffer.RemoveFromStart(bool.FalseString.Length);
				}
				else if (buffer[0] == '0')
				{
					// Is already 0, sooOOo nothing to do here
					buffer.RemoveFromStart(1);
				}
				else LogErrorReturn!("Failed to parse bool");
			}
			else if (valType is SizedArrayType)
			{
				ForceEat!('[', ref buffer);
				EatSpace!(ref buffer);

				let t = (SizedArrayType)valType;
				let count = t.ElementCount;
				let arrType = t.UnderlyingType;

				var i = 0;
				var ptr = (uint8*)val.DataPtr;
				while ({
					EatSpace!(ref buffer);
					buffer[0] != ']'
					})
				{
					if (i >= count)
						LogErrorReturn!("Too many elements given in array");

					var arrVal = Variant.CreateReference(arrType, ptr);
					Try!(Value(scene, ref arrVal, ref buffer, deferResolveEntityRefs));

					ptr += arrType.Size;
					i++;

					EatSpace!(ref buffer);

					if (buffer[0] == ',')
						buffer.RemoveFromStart(1);
				}

				ForceEat!(']', ref buffer);
			}
			else if (valType.IsEnum)
			{
				// Get enum value
				var enumLen = 0, isNumber = true;
				for (; enumLen < buffer.Length; enumLen++)
					if (!buffer[enumLen].IsDigit)
					{
						if (!buffer[enumLen].IsLetter && buffer[enumLen] != '_')
							break;
						else isNumber = false;
					}

				if (enumLen == 0)
					LogErrorReturn!("Expected enum value");

				let enumVal = buffer.Substring(0, enumLen);
				buffer.RemoveFromStart(enumLen);

				if (isNumber)
				{
					if (valType.IsSigned)
					{
						if (int64.Parse(enumVal) case .Ok(var num))
							Internal.MemCpy(val.DataPtr, &num, valType.Size);
						else LogErrorReturn!("Failed to parse enum integer");
					}
					else
					{
						if (uint64.Parse(enumVal) case .Ok(var num))
							Internal.MemCpy(val.DataPtr, &num, valType.Size);
						else LogErrorReturn!("Failed to parse enum integer");
					}
				}
				else
				{
					FINDFIELD:do
					{
						let typeInst = (TypeInstance)valType;
						for (let field in typeInst.GetFields())
						{
							if (enumVal.Equals(field.[Friend]mFieldData.mName, false))
							{
								Internal.MemCpy(val.DataPtr, &field.[Friend]mFieldData.mData, valType.Size);
								break FINDFIELD;
							}
						}

						LogErrorReturn!("Failed to parse enum string");
					}
				}
			}
			else if (valType == typeof(String)
				|| valType == typeof(StringView))
			{
				if (buffer[0] != '"')
					LogErrorReturn!("String must start with '\"'");

				// Find terminating "
				int endIdx = -1;
				bool isEscape = false;
				for (let c in buffer[1...])
				{
					if (c == '"' && !isEscape)
					{
						endIdx = @c.Index;
						break;
					}	

					if (c == '\\')
						isEscape = true;
					else isEscape = false;
				}
				if (endIdx == -1)
					LogErrorReturn!("Unterminated string in asset notation");

				// Manage string!
				var nameStr = String.UnQuoteString(&buffer[0], endIdx + 2, .. scope .());
				if (scene.managedStrings.Contains(nameStr))
				{
					Debug.Assert(!scene.managedStrings.TryAdd(nameStr, let existantStr));

					nameStr = *existantStr;
				}
				else
				{
					// Allocate new one, doesnt currently exist!
					nameStr = scene.managedStrings.Add(.. new .(nameStr));
				}

				if (valType == typeof(StringView))
				{
					// Make and copy stringView
					var strVal = (StringView)nameStr;
					Internal.MemCpy(val.DataPtr, &strVal, sizeof(StringView));
				}
				else
				{
					// Copy pointer to string
					Internal.MemCpy(val.DataPtr, &nameStr, sizeof(int));
				}

				buffer.RemoveFromStart(endIdx + 2);
			}
			else if (valType.IsStruct)
			{
				Try!(Struct(scene, valType, .((uint8*)val.DataPtr, valType.Size), ref buffer, deferResolveEntityRefs));
			}
			else LogErrorReturn!("Cannot handle value");

			return .Ok;
		}

		static Result<void> Struct(BonReader reader, ref Variant val)
		{
			let structType = val.VariantType;
			using (let block = reader.ObjectBlock())
			{
				while (block.HasMore())
				{
					let name = reader.Identifier();

					FieldInfo fieldInfo;
					switch (structType.GetField(scope .(name)))
					{
					case .Ok(let field):
						fieldInfo = field;
					case .Err:
						// TODO: proper errors
						return .Err; // Field does not exist
					}

					Variant fieldVal = Variant.CreateReference(fieldInfo.FieldType, ((uint8*)val.DataPtr) + fieldInfo.MemberOffset);

					Try!(Value(reader, ref fieldVal));

					if (block.HasMore())
						reader.EntryEnd();

					if (reader.HadErrors())
						return .Err;
				}
			}

			return .Ok;
		}
	}
}