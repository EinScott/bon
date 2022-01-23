using System;
using Bon;
using System.Diagnostics;
using System.Collections;

/*namespace System
{
	// TODO: buildsettings include or this DOES NOT WORK: both link error!
	[Serializable]
	extension String
	{

	}
}*/

namespace Bon.Tests
{
	static
	{
		struct PushFlags : IDisposable
		{
			BonSerializeFlags old;

			[Inline]
			public this(BonSerializeFlags flags)
			{
				old = gBonEnv.serializeFlags;
				gBonEnv.serializeFlags = flags;
			}

			[Inline]
			public void Dispose()
			{
				gBonEnv.serializeFlags = old;
			}
		}

		static StringView HandleStringView(StringView view)
		{
			// Since we're dealing with const strings,
			// just intern the deserialized views to get
			// back the exact string literal
			return view.Intern();
		}

		static List<String> strings = new .() ~ DeleteContainerAndItems!(_);

		static void MakeString(Variant val)
		{
			var val;
			var str = strings.Add(.. new .());

			*(String*)val.DataPtr = str;
		}

		static void DestroyString(Variant val)
		{
			var val;
			var str = *((String*)val.DataPtr);

			if (strings.Remove(str))
				delete str; // We allocated it!
		}

		static mixin SetupStringViewHandler()
		{
			gBonEnv.stringViewHandler = => HandleStringView;

			gBonEnv.instanceHandlers.Remove(typeof(String));
			BonEnvironment.MakeThing make = => MakeString;
			BonEnvironment.DestroyThing destroy = => DestroyString;

			gBonEnv.instanceHandlers.Add(typeof(String), (make, destroy));
		}

		static void MakeStringFix(Variant val)
		{
			var val;
			*(String*)val.DataPtr = new String();
		}

		static mixin NoStringHandler()
		{
			gBonEnv.stringViewHandler = => HandleStringView;

			// TODO This is a fix for not being able to force reflection data on these types currently, see bug at top of file!

			gBonEnv.instanceHandlers.Remove(typeof(String));
			BonEnvironment.MakeThing make = => MakeStringFix;

			gBonEnv.instanceHandlers.Add(typeof(String), (make, null));
		}

		[Test]
		static void Primitives()
		{
			{
				int32 i = 357;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "357");

				int32 oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
			}

			{
				char8 c = '\n';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'\\n'");

				char8 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}

			{
				char8 c = '\'';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'\\''");

				char8 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}

			using (PushFlags(.IncludeDefault))
			{
				char8 c = '\0';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'\\0'");

				char8 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}
			
			{
				char16 c = 'Ā';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'Ā'");

				char16 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}
			
			{
				char16 c = 'ģ';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'ģ'");

				char16 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}

			{
				char16 c = 'ァ';
				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "'ァ'");

				char16 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, str) case .Ok) && oc == c);
			}

			using (PushFlags(.Verbose))
			{
				bool b = true;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str == bool.TrueString);

				bool ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, str) case .Ok) && ob == b);
			}

			{
				bool b = true;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str == "1");

				bool ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, str) case .Ok) && ob == b);
			}

			{
				bool b = false;
				let str = Bon.Serialize(b, .. scope .());
				Test.Assert(str.Length == 0); // Should not be included -> false is default

				bool ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, str) case .Ok) && ob == b);
			}

			{
				float ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, "1f") case .Ok) && ob == 1f);
			}

			{
				int i = ?;
				Test.Assert((Bon.Deserialize(ref i, "\t11 ") case .Ok) && i == 11);
			}

			{
				int i = ?;
				Test.Assert((Bon.Deserialize(ref i, "default") case .Ok) && i == 0);
			}

			// Should error (but not crash)

			{
				bool ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, "223") case .Err));
			}

			{
				char8 ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, "'") case .Err));
			}
		}

		[Test]
		static void Strings()
		{
			SetupStringViewHandler!();

			{
				StringView s = "A normal string";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"A normal string\"");

				StringView so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			{
				String s = "A normal string";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"A normal string\"");

				String so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			{
				StringView s = "";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"\"");

				StringView so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			{
				StringView s = .() {Length = 1};
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "null");

				StringView so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so.Ptr == null);
			}
		}

		[Test]
		static void Arrays()
		{
			{
				uint8[6] s = .(12, 24, 53, 34,);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "[12,24,53,34]");

				uint8[6] so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			using (PushFlags(.Verbose))
			{
				uint8[6] s = .(12, 24, 53, 34,);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<const 6>[12,24,53,34]");

				uint8[6] so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			{
				uint16[4] s = .(345, 2036, 568, 3511);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "[345,2036,568,3511]");

				uint16[4] so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			using (PushFlags(.Verbose))
			{
				SetupStringViewHandler!();

				StringView[4] s = .("hello", "second String", "another entry", "LAST one");
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == """
					<const 4>[
						\"hello\",
						\"second String\",
						\"another entry\",
						\"LAST one\"
					]
					""");

				StringView[4] so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && s == so);
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
			Hut = 1 << 1,
			Green = 1 << 2,
			Street = 1 << 3,
			Tram = 1 << 4,
			Path = 1 << 5,
			Tree = 1 << 6,
			Water = 1 << 7,

			SeasideHouse = .House | .Water,
			Park = .Path | .Tree | .Green,
			CozyHut = .Hut | .Tree | .Water | .Path,
			Rural = .House | .Green | .Street,
			City = .House | .Street | .Tram,
			Forest = .Tree | .Path,
		}

		[Serializable]
		enum SomeTokens : char8
		{
			Dot = '.',
			Slash = '/',
			Dash = '-'
		}

		[Test]
		static void Enums()
		{
			// No reflection data
			{
				TypeA i = .Named120;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "120");

				TypeA oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
			}

			// Not verbose
			{
				TypeB i = .Count;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "2");

				TypeB oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
			}

			using (PushFlags(.Verbose))
			{
				{
					TypeB i = .Count;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Count");

					TypeB oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				using (PushFlags(.Verbose|.IncludeDefault))
				{
					SomeValues i = default;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Option1");

					SomeValues oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					SomeValues i = .Option2;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Option2");

					SomeValues oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					SomeValues i = (.)12; // Does not have bits of 1 & 2 set, so it won't find any match
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == "12");

					SomeValues oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					SomeValues i = (.)5; // Shares a bit with Option2 (1), and prints remainder
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Option2|4");

					SomeValues oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					SomeValues i = (.)15;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Option2|.Option3|12");

					SomeValues oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					PlaceFlags i = .Park;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Park");

					PlaceFlags oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					PlaceFlags i = .House | .Street | .Tram;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".City");

					PlaceFlags oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					PlaceFlags i = .SeasideHouse | .Forest;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".SeasideHouse|.Forest");

					PlaceFlags oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					PlaceFlags i = .CozyHut | .Rural;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".CozyHut|.Rural");

					PlaceFlags oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					PlaceFlags i = .Park | .CozyHut; // They have overlap
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".CozyHut|.Green");

					PlaceFlags oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}

				{
					SomeTokens i = .Dot;
					let str = Bon.Serialize(i, .. scope .());
					Test.Assert(str == ".Dot");

					SomeTokens oi = ?;
					Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
				}
			}

			{
				SomeTokens i = .Slash;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "'/'");

				SomeTokens oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
			}

			{
				PlaceFlags oi = ?;

				Test.Assert((Bon.Deserialize(ref oi, "1 | 2 | 4") case .Ok) && oi == (.)(1 | 2 | 4));
				Test.Assert((Bon.Deserialize(ref oi, "1 | .Water") case .Ok) && oi == .SeasideHouse);
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

		[Serializable]
		struct SomeData
		{
			public double time;
			public uint64 value;
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

					SomeThings so = ?;
					so.str = scope .();
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
				}

				using (PushFlags(.AllowNonPublic))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656}");

					SomeThings so = ?;
					so.str = scope .();
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
				}

				using (PushFlags(.IncludeDefault))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",important=32656,n=0}");

					SomeThings so = default; // All of these need to be nulled so that the string pointer is not pointing somewhere random!
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
				}

				using (PushFlags(.IgnoreAttributes))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",dont=8}");

					SomeThings so = default;
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
				}

				using (PushFlags(.AllowNonPublic|.IgnoreAttributes|.IncludeDefault))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656,dont=8,n=0}");

					SomeThings so = default;
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
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

					StructA so = default;
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && s == so);
				}

				using (PushFlags(.Verbose))
				{
					let str = Bon.Serialize(s, .. scope .());
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

					StructA so = default;
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str && s == so);
				}
			}

			{
				let s = SomeData(){
					time = 65.5,
					value = 11917585743392890597
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{time=65.5,value=11917585743392890597}");

				SomeData so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
				Test.Assert((Bon.Deserialize(ref so, "{time=6.55e1d,value=11917585743392890597,}") case .Ok) && so == s);
				Test.Assert((Bon.Deserialize(ref so, """
					{ // look, a comment! }
						time=6.55e1d /* hello! */,
						value=11917585743392890597,
					}
					""") case .Ok) && so == s);
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
			using (PushFlags(.IncludeDefault))
			{
				Thing i = .Nothing;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Nothing{}");

				Thing si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);

				Test.Assert((Bon.Deserialize(ref si, "default") case .Ok) && si == i);
			}

			{
				Thing i = .Circle(.(0, 0), 4.5f);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Circle{radius=4.5}");

				Thing si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}

			{
				SetupStringViewHandler!();

				Thing i = .Text(.(50, 50), "Something\"!", 24, 90f);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Text{pos={x=50,y=50},text=\"Something\\\"!\",size=24,rotation=90}");

				Thing si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}

			{
				Thing i = .Something(5, 4.5f, .(1, 10));
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Something{0=5,1=4.5,2={x=1,y=10}}");

				Thing si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}

			using (PushFlags(.Verbose))
			{
				Thing i = .Circle(.(10, 1), 4.5f);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == """
					.Circle{
						pos={
							x=10,
							y=1
						},
						radius=4.5
					}
					""");

				Thing si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}
		}

		[Test]
		public static void Boxed()
		{
			{
				let s = scope box SomeData(){
					time = 65.5,
					value = 11917585743392890597
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{time=65.5,value=11917585743392890597}");
			}

			{
				var i = scope box int(357);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "357");

				// TODO: this would need polymorphism!
				/*Object oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);*/
			}
		}

		[Serializable]
		class AClass
		{
			public String aStringThing ~ if (_ != null) delete _;
			public uint8 thing;
			public SomeData data;
		}

		[Test]
		static void Classes()
		{
			// TODO:
			// also use default when serializing IncludeDefault for structs/classes & arrays! - introduce ForceFullTree or something to make it still print everything!

			// TODO: test with inheritance, polymorphism...
			// polymorphism i going to be big problem
			// we need something to record type info?
			// -> i mean, what if it's some base type array with different things in it
			// then we need basically the notation we just for scenes right now?
			// -> yea we do that, and types used for it/in it must be explicitly marked
			//    alternatively everything can be marked. Lib-types can be marked with a
			//    mixin to add to global context, or just adding to a custom context or
			//    global env manually

			// => then do polymorphism (arrays, objects... classes & boxed stuff)
			// => then other bon envc stuff

			NoStringHandler!();

			// TODO: some tests for deleting stuff though bon (deallocate/destroy)
			// and also if strings just created by bon leak

			{
				let c = scope AClass() { thing = uint8.MaxValue, data = .{ value = 10, time = 1 }, aStringThing = new .("A STRING THING yes") };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "{aStringThing=\"A STRING THING yes\",thing=255,data={time=1,value=10}}");

				AClass co = scope .();
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && co.thing == c.thing && co.data == c.data && c.aStringThing == c.aStringThing);
			}
		}

		[Test]
		static void Trash()
		{
			int i = ?;
			char16 c = ?;
			StringView s = ?;
			SomeValues e = ?;
			SomeData d = ?;
			uint8[2] a = ?;
			SomeData[2] ad = ?;

			Test.Assert(Bon.Deserialize(ref i, "11 34") case .Err);
			Test.Assert(Bon.Deserialize(ref i, "  11.") case .Err);

			Test.Assert(Bon.Deserialize(ref s, "\"") case .Err);
			Test.Assert(Bon.Deserialize(ref s, "\"egnionsoibe") case .Err);
			Test.Assert(Bon.Deserialize(ref s, "\"egniod d  nsoibe") case .Err);
			Test.Assert(Bon.Deserialize(ref s, "  \"eg\\\"") case .Err);
			Test.Assert(Bon.Deserialize(ref s, ",") case .Err);

			Test.Assert(Bon.Deserialize(ref c, "\'\'") case .Err);
			Test.Assert(Bon.Deserialize(ref c, "\'ad\'") case .Err);
			Test.Assert(Bon.Deserialize(ref c, "ad\'") case .Err);
			Test.Assert(Bon.Deserialize(ref c, " '\\\'  \t\n") case .Err);

			Test.Assert(Bon.Deserialize(ref e, ".") case .Err);
			Test.Assert(Bon.Deserialize(ref e, " .\t ") case .Err);
			Test.Assert(Bon.Deserialize(ref e, " .ad\t ") case .Err);
			Test.Assert(Bon.Deserialize(ref e, " .3\t ") case .Err);
			Test.Assert(Bon.Deserialize(ref e, " .||.|3,\t ") case .Err);
			Test.Assert(Bon.Deserialize(ref e, "|") case .Err);
			Test.Assert(Bon.Deserialize(ref e, "234|.2") case .Err);
			Test.Assert(Bon.Deserialize(ref e, "34  |\t'") case .Err);
			Test.Assert(Bon.Deserialize(ref e, "23 '|") case .Err);

			Test.Assert(Bon.Deserialize(ref d, "{{]") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{,}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{,,}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{,,") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{,,,}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{0,,,}") case .Err);

			Test.Assert(Bon.Deserialize(ref a, "[") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "[,]") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "[,,]") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "[,") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "[,0]") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "[1,1,1,]") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "<[1,1,1,]") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "<>") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "<a>[") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "<-2>[") case .Err);
			Test.Assert(Bon.Deserialize(ref a, "<const>[") case .Err);

			Test.Assert(Bon.Deserialize(ref ad, "[{,") case .Err);
			Test.Assert(Bon.Deserialize(ref ad, "[{},0]") case .Err);
			Test.Assert(Bon.Deserialize(ref ad, "[{aa=1}]") case .Err);
			Test.Assert(Bon.Deserialize(ref ad, "[{value=\"\"}]") case .Err);
			Test.Assert(Bon.Deserialize(ref ad, "[{}{}]") case .Err);
			
			Test.Assert(Bon.Deserialize(ref a, "<const12>[]") case .Ok); // There is no reason for this to work, but also none for it to not work
			Test.Assert(Bon.Deserialize(ref a, "<1>[]") case .Ok);
			Test.Assert(Bon.Deserialize(ref i, " \n\t") case .Ok);
		}

		[Test]
		static void Bench()
		{
			// TODO
		}
	}
}
