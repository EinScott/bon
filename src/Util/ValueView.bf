using System;
using System.Diagnostics;
using Bon.Integrated;

namespace Bon
{
	// A reference to a value in memory. For structs, this is the struct body obviously (StringView* => void*).
	// For classes, this is the pointer/reference to their body (String* => void**), just as things would be
	// if you looked at the members of something.
	struct ValueView
	{
		public void* dataPtr;
		public Type type;

		[Inline]
		public this(Type type, void* dataPtr)
		{
			this.dataPtr = dataPtr;
			this.type = type;
		}

		public void Assign<T>(T value)
		{
			Debug.Assert(type.IsSubtypeOf(typeof(T)));
			*(T*)dataPtr = value;
		}

		public T Get<T>()
		{
			var thing = *(T*)dataPtr;

			if (typeof(T).IsObject)
				Debug.Assert(thing.GetType().IsSubtypeOf(typeof(T)));

			return thing;
		}

		[Inline]
		// Invoke expects a pointer to the data, not the "field"/pointer to it. So for objects, we need to lower by one level.
		public Variant ToInvokeVariant() => Variant.CreateReference(type, TypeHoldsObject!(type) ? *(void**)dataPtr : dataPtr);
	}
}