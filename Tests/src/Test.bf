using System;
using Bon;
using System.Diagnostics;

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
				char8 c = '\n';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'\\n'");
			}

			{
				char16 c = 'ァ';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'ァ'");
			}

			{
				bool b = true;
				let str = Bon.Serialize(b, .. scope .(), .Verbose);
				Test.Assert(str == bool.TrueString);
			}

			{
				bool b = true;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str == "1");
			}

			{
				bool b = false;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str.Length == 0); // Should not be included -> false is default
			}
		}

		[Test]
		static void Strings()
		{
			{
				StringView s = "A normal string";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"A normal string\"");
			}

			{
				StringView s = "";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"\"");
			}

			{
				StringView s = .() {Length = 1};
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "null");
			}
		}

		[Test]
		static void Arrays()
		{
			{
				uint8[6] s = .(12, 24, 53, 34,);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "[12,24,53,34]");
			}

			{
				uint8[6] s = .(12, 24, 53, 34,);
				let str = Bon.Serialize(s, .. scope .(), .Verbose);
				Test.Assert(str == "<const 6>[12,24,53,34]");
			}

			{
				uint16[4] s = .(345, 2036, 568, 3511);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "[345,2036,568,3511]");
			}

			{
				String[4] s = .("hello", "second String", "another entry", "LAST one");
				let str = Bon.Serialize(s, .. scope .(), .Verbose);
				Test.Assert(str == """
					<const 4>[
						\"hello\",
						\"second String\",
						\"another entry\",
						\"LAST one\"
					]
					""");
			}
		}

		enum TypeA : int8
		{
			Named16 = 16,
			Named120 = 120
		}

		[Serializable]
		enum TypeB : uint16
		{
			AThing,
			OtherThing,
			Count
		}

		[Serializable]
		enum SomeValues
		{
			public const SomeValues defaultOption = .Option2;

			case Option1;
			case Option2;
			case Option3;
		}

		[Serializable]
		enum PlaceFlags
		{
			None = 0,
			House = 1,
			Hut = 1 << 2,
			Green = 1 << 3,
			Street = 1 << 4,
			Tram = 1 << 5,
			Path = 1 << 6,
			Tree = 1 << 7,
			Water = 1 << 8,

			SeasideHouse = .House | .Water,
			Park = .Path | .Tree | .Green,
			CozyHut = .Hut | .Tree | .Water | .Path,
			Rural = .House | .Green | .Street,
			City = .House | .Street | .Tram,
			Forest = .Tree | .Path,
		}

		[Test]
		static void Enums()
		{
			// No reflection data
			{
				TypeA i = .Named120;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "120");
			}

			// Not verbose
			{
				TypeB i = .Count;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "2");
			}

			{
				TypeB i = .Count;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".Count");
			}

			{
				SomeValues i = .Option2;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".Option2");
			}

			{
				PlaceFlags i = .Park;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".Park");
			}

			{
				PlaceFlags i = .House | .Street | .Tram;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".City");
			}

			{
				PlaceFlags i = .SeasideHouse | .Forest;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".SeasideHouse|.Forest");
			}

			{
				PlaceFlags i = .CozyHut | .Rural;
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".CozyHut|.Rural");
			}

			{
				PlaceFlags i = .Park | .CozyHut; // They have overlap
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == ".CozyHut|.Green");
			}
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
					Test.Assert(str == "{thing=651,bs=[{name=\"first element\",age=34,type=1},{name=\"second element\",age=101},{name=\"\"}]}");
				}

				{
					let str = Bon.Serialize(s, .. scope .(), .Verbose);
					Test.Assert(str == """
						{
							thing=651,
							bs=<const 5>[
								{
									name="first element",
									age=34,
									type=.OtherThing
								},
								{
									name="second element",
									age=101
								},
								{
									name=""
								}
							]
						}
						""");
				}
			}
		}

		[Serializable]
		struct Vector2 : this(float x, float y);

		[Serializable]
		enum Thing
		{
			case Nothing;
			case Text(Vector2 pos, String text, int size, float rotation);
			case Circle(Vector2 pos, float radius);
			case Something(float, float, Vector2);
		}

		[Test]
		static void EnumUnions()
		{
			{
				Thing i = .Nothing;
				let str = Bon.Serialize(i, .. scope .(), .IncludeDefault);
				Test.Assert(str == ".Nothing{}");
			}

			{
				Thing i = .Circle(.(0, 0), 4.5f);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Circle{radius=4.5}");
			}

			{
				Thing i = .Text(.(50, 50), "Something!", 24, 90f);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Text{pos={x=50,y=50},text=\"Something!\",size=24,rotation=90}");
			}

			{
				Thing i = .Something(5, 4.5f, .(1, 10));
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Something{0=5,1=4.5,2={x=1,y=10}}");
			}

			{
				Thing i = .Circle(.(10, 1), 4.5f);
				let str = Bon.Serialize(i, .. scope .(), .Verbose);
				Test.Assert(str == """
					.Circle{
						pos={
							x=10,
							y=1
						},
						radius=4.5
					}
					""");
			}
		}
	}
}
