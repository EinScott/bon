using System;
using Bon;

namespace Bon.Tests
{
	static
	{
		[Test]
		static void Primitives()
		{
			{
				int32 i = 357;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "357");
			}

			{
				bool b = true;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str == bool.TrueString);
			}

			{
				bool b = false;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str.Length == 0); // Should not be included -> false is default
			}
		}

		[Test]
		static void Enums()
		{

		}

		[Test]
		static void Strings()
		{

		}

		[Test]
		static void Arrays()
		{

		}

		[Serializable,Ordered]
		struct SomeThings
		{
			public int i;
			public float f;
			public String str;

			uint8 intern;

			[DoSerialize]
			uint16 important;

			[NoSerialize]
			public uint dont;

			public int8 n;
		}

		[Serializable]
		struct StructA
		{
			public int thing;
			public StructB[5] bs;
		}

		[Serializable]
		enum TypeB : uint16
		{
			AThing,
			OtherThing,
			Count
		}

		[Serializable]
		struct StructB
		{
			public StringView name;
			public uint8 age;
			public TypeB type;
		}

		[Test]
		static void Structs()
		{
			{
				var s = SomeThings{
					i = 5,
					f = 1,
					str = "oh hello",
					dont = 8
				};
				s.[Friend]intern = 54;
				s.[Friend]important = 32656;

				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",important=32656}");
				}

				{
					let str = Bon.Serialize(s, .. scope .(), .AllowNonPublic);
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656}");
				}

				{
					let str = Bon.Serialize(s, .. scope .(), .IncludeDefault);
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",important=32656,n=0}");
				}

				{
					let str = Bon.Serialize(s, .. scope .(), .IgnoreAttributes);
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",dont=8}");
				}

				{
					let str = Bon.Serialize(s, .. scope .(), .AllowNonPublic|.IgnoreAttributes|.IncludeDefault);
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656,dont=8,n=0}");
				}
			}

			{
				var s = StructA{
					thing = 651,
					bs = .(.{
						name = "first element",
						age = 34,
						type = .OtherThing
					}, .{
						name = "second element",
						age = 101,
						type = .AThing
					}, .{
						name = ""
					},)
				};

				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{thing=651,bs=[{name=\"first element\",age=34,type=.OtherThing},{name=\"second element\",age=101},{name=\"\"}]}");
				}
			}
		}
	}
}
