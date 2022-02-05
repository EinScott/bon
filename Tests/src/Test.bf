using System;
using Bon;
using System.Diagnostics;
using System.Collections;

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

		struct PushDeFlags : IDisposable
		{
			BonDeserializeFlags old;

			[Inline]
			public this(BonDeserializeFlags flags)
			{
				old = gBonEnv.deserializeFlags;
				gBonEnv.deserializeFlags = flags;
			}

			[Inline]
			public void Dispose()
			{
				gBonEnv.deserializeFlags = old;
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

		static void MakeString(ValueView val)
		{
			var val;
			var str = strings.Add(.. new .());

			val.Assign(str);
		}

		static void DestroyString(ValueView val)
		{
			var val;
			var str = val.Get<String>();

			if (strings.Remove(str))
				delete str; // We allocated it!
		}

		static mixin SetupStringHandler()
		{
			gBonEnv.stringViewHandler = => HandleStringView;

			if (!gBonEnv.instanceHandlers.ContainsKey(typeof(String)))
				gBonEnv.instanceHandlers.Add(typeof(String), ((.)new => MakeString, (.)new => DestroyString));
		}

		static mixin NoStringHandler()
		{
			gBonEnv.stringViewHandler = => HandleStringView;
			gBonEnv.instanceHandlers.Remove(typeof(String));
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
				int32 i = -67;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "-67");

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
				Test.Assert(str == "?"); // Should not be included -> false is default

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
				Test.Assert((Bon.Deserialize(ref i, "0xF5aL") case .Ok) && i == 3930);
			}

			{
				int8 i = ?;
				Test.Assert((Bon.Deserialize(ref i, "0b1'0'1") case .Ok) && i == 5);
			}

			{
				uint8 i = ?;
				Test.Assert((Bon.Deserialize(ref i, "0o75UL") case .Ok) && i == 61);
			}

			{
				int i = ?;
				Test.Assert((Bon.Deserialize(ref i, "default") case .Ok) && i == 0);
			}

			{
				char32 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, "'\\u{10FFFF}'") case .Ok) && oc == '\u{10FFFF}');
			}

			{
				char32 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, "'\\u{30A1}'") case .Ok) && oc == '\u{30A1}');
			}

			{
				char8 oc = ?;
				Test.Assert((Bon.Deserialize(ref oc, "'\\x2a'") case .Ok) && oc == '\x2a');
			}

			// Should error (but not crash)

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "299") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "-25u") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "0b2") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "0xg") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "0o8") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'Ā'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\x'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\x2'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\x2z'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\x2aa'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\u'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\u{'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\u{}'") case .Err);
			}

			{
				char8 oc = ?;
				Test.Assert(Bon.Deserialize(ref oc, "'\\u{5g}'") case .Err);
			}

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
			SetupStringHandler!();

			{
				StringView s = "A normal string	";
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "\"A normal string\\t\"");

				StringView so = ?;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == s);
			}

			{
				StringView s = @"S:\ome\Path\To.file";
				StringView so = ?;
				Test.Assert((Bon.Deserialize(ref so, "@\"S:\\ome\\Path\\To.file\"") case .Ok) && so == s);
				Test.Assert((Bon.Deserialize(ref so, "\"S:\\\\ome\\\\Path\\\\To.file\"") case .Ok) && so == s);
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

			using (PushFlags(.IncludeDefault))
			{
				String s = null;
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "null"); // Without .IncludeDefault, this naturally would be '?'

				String so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && so == null);
			}

			{
				StringView so = ?;
				Test.Assert(Bon.Deserialize(ref so, """
					"Some string
					"
					""") case .Err);
			}

			{
				StringView so = ?;
				Test.Assert(Bon.Deserialize(ref so, """
					"Some string	" // Beef allows this too, so...
					""") case .Ok);
			}
		}

		[Test]
		static void SizedArrays()
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
				SetupStringHandler!();

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

		[Serializable,PolySerialize] // Also used for boxing tests
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

		[Serializable,PolySerialize] // Also use it for boxing tests
		struct SomeData : IThing
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

				using (PushFlags(.IncludeNonPublic))
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

				using (PushFlags(.IncludeNonPublic|.IgnoreAttributes|.IncludeDefault))
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
					}, default, .{
						name = ""
					},)
				};

				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{thing=651,bs=[{name=\"first element\",age=34,type=1},{name=\"second element\",age=101},?,{name=\"\"}]}");

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
								?,
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

		[Serializable, PolySerialize]
		enum Thing
		{
			case Nothing;
			case Text(Vector2 pos, String text, int size, float rotation);
			case Circle(Vector2 pos, float radius);
			case Something(float, float, Vector2);
		}

		enum Carry
		{
			case One(int);
			case Two(String);
			case Three(uint8[]);
		}

		[Test]
		static void EnumUnions()
		{
			// No reflection data
			using (PushFlags(.IncludeDefault))
			{
				Carry i = .One(1);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".One{0=1}");

				Carry si = ?;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}

			using (PushFlags(.IncludeDefault))
			{
				Thing i = .Nothing;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Nothing{}");

				Thing si = .Circle(.(0, 0), 4.5f);
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
				si = .Circle(.(0, 0), 4.5f);
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
				SetupStringHandler!();

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
		static void Boxed()
		{
			{
				Object s = scope box SomeData(){
					time = 65.5,
					value = 11917585743392890597
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "(Bon.Tests.SomeData){time=65.5,value=11917585743392890597}");

				Object os = null;
				Test.Assert((Bon.Deserialize(ref os, str) case .Ok) && os.GetType() == s.GetType() && Bon.Serialize(os, .. scope .()) == str);
				delete os;
			}

			{
				Object i = scope box int(357);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "(System.Int)357");

				Object oi = null;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi.GetType() == i.GetType() && Bon.Serialize(oi, .. scope .()) == str);
				delete oi;
			}

			{
				var i = scope box SomeTokens.Dash;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "(Bon.Tests.SomeTokens)'-'");

				Object oi = scope box SomeTokens.Slash;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi.GetType() == i.GetType() && Bon.Serialize(oi, .. scope .()) == str);
			}

			using (PushFlags(.Verbose))
			{
				Object i = scope box SomeTokens.Dash;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "(Bon.Tests.SomeTokens).Dash");

				Object oi = null;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi.GetType() == i.GetType() && Bon.Serialize(oi, .. scope .()) == str);
				delete oi;
			}

			{
				Object i = scope box Thing.Circle(.(20, 50), 1);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "(Bon.Tests.Thing).Circle{pos={x=20,y=50},radius=1}");

				Object oi = new box SomeTokens.Dash; // oops- wrong type
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi.GetType() == i.GetType() && Bon.Serialize(oi, .. scope .()) == str);
				delete oi;
			}
		}

		[Serializable,PolySerialize]
		class AClass
		{
			public String aStringThing ~ if (_ != null) delete _;
			public uint8 thing;
			public SomeData data;
		}

		[Serializable] // Base classes also need to be marked!
		abstract class BaseThing
		{
			public abstract int Number { get; set; }

			public String Name = new .("nothing") ~ delete _;
		}

		interface IThing
		{

		}

		[Serializable,PolySerialize]
		class OtherClassThing : BaseThing, IThing
		{
			public uint32 something;

			public override int Number { get; set; }
		}

		[Serializable]
		class FinClass : OtherClassThing
		{
			public new uint64 something;
		}

		[Serializable,PolySerialize]
		class LookAThing<T>
		{
			T tThingLook;
		}

		[Test]
		static void Classes()
		{
			NoStringHandler!();

			{
				let c = scope AClass() { thing = uint8.MaxValue, data = .{ value = 10, time = 1 }, aStringThing = new .("A STRING THING yes") };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "{aStringThing=\"A STRING THING yes\",thing=255,data={time=1,value=10}}");

				AClass co = scope .();
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && co.thing == c.thing && co.data == c.data && c.aStringThing == c.aStringThing);
			}

			{
				Object c = scope AClass() { thing = uint8.MaxValue, data = .{ value = 10, time = 1 }, aStringThing = new .("A STRING THING yes") };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.AClass){aStringThing=\"A STRING THING yes\",thing=255,data={time=1,value=10}}");

				Object co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == str);
				delete co;
			}

			using (PushFlags(.IncludeNonPublic))
			{
				OtherClassThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };
				c.Name.Set("ohh");

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "{something=222252222,prop__Number=59992,Name=\"ohh\"}");

				OtherClassThing co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == str);
				delete co;
			}

			using (PushFlags(.IncludeNonPublic))
			{
				Object c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,prop__Number=59992,Name=\"nothing\"}");

				Object co = new AClass(); // oops.. wrong type there!
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == str);
				delete co;
			}

			using (PushFlags(.IncludeNonPublic))
			{
				BaseThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,prop__Number=59992,Name=\"nothing\"}");

				BaseThing co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == str);
				delete co;
			}

			{
				BaseThing c = scope FinClass() { something = 222252222, @something = 26 };
				c.Name.Set("fin");

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.FinClass){something=222252222,something=26,Name=\"fin\"}");

				// This is dependent on the order of the two "something"s. It's cursed, but
				// I'm still glad it just works. Outermost class' fields first, then down the inheritance tree
				FinClass co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == "{something=222252222,something=26,Name=\"fin\"}");
				delete co;
			}

			using (PushFlags(.IncludeNonPublic))
			{
				let c = scope LookAThing<int>();
				c.[Friend]tThingLook = 55;

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "{tThingLook=55}");

				LookAThing<int> co = scope .();
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && co.[Friend]tThingLook == c.[Friend]tThingLook);
			}

			using (PushFlags(.IncludeNonPublic))
			TEST: {
				Object c = { let a = scope:TEST LookAThing<int>(); a.[Friend]tThingLook = 55; a };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.LookAThing<int>){tThingLook=55}");

				Object co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && Bon.Serialize(co, .. scope .()) == "(Bon.Tests.LookAThing<int>){tThingLook=55}");
				delete co;
			}
		}

		[Test]
		static void Interfaces()
		{
			using (PushFlags(.IncludeNonPublic))
			{
				IThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,prop__Number=59992,Name=\"nothing\"}");

				IThing co = null;
				Test.Assert((Bon.Deserialize(ref co, str) case .Ok) && c.GetType() == co.GetType() && Bon.Serialize(co, .. scope .()) == str);
				delete co;
			}

			{
				IThing s = scope box SomeData(){
					time = 65.5,
					value = 11917585743392890597
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "(Bon.Tests.SomeData){time=65.5,value=11917585743392890597}");

				IThing os = null;
				Test.Assert((Bon.Deserialize(ref os, str) case .Ok) && os.GetType() == s.GetType() && Bon.Serialize(os, .. scope .()) == str);
				delete os;
			}

			{
				IThing s = SomeData(){
					time = 65.5,
					value = 11917585743392890597
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "(Bon.Tests.SomeData){time=65.5,value=11917585743392890597}");

				IThing os = null;
				Test.Assert((Bon.Deserialize(ref os, str) case .Ok) && os.GetType() == s.GetType() && Bon.Serialize(os, .. scope .()) == str);
				delete os;
			}

			{
				IThing os = null;
				Test.Assert(Bon.Deserialize(ref os, "{time=65.5,value=11917585743392890597}") case .Err);
			}
		}

		static mixin ArrayEqual<T>(T a, T b) where T : var
		{
			bool equal = true;
			if (a.Count != b.Count)
				equal = false;
			else
			{
				for (int i < a.Count)
					if (a[i] != b[i])
					{
						equal = false;
						break;
					}
			}
			equal
		}

		[Test]
		static void Arrays()
		{
			{
				uint8[] s = scope .();
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<0>[]");

				uint8[] so = scope .[0];
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
			}

			{
				// Infer size to be 0

				uint8[] so = null;
				Test.Assert((Bon.Deserialize(ref so, "[ ]") case .Ok) && so.Count == 0);
				delete so;
			}

			{
				uint8[] s = scope .(12, 24, 53, 34, 5, 0, 0);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<7>[12,24,53,34,5]");

				uint8[] so = scope .[7];
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
			}

			{
				uint8[] s = scope .(12, 24, 53, 34, 5, 0, 0);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<7>[12,24,53,34,5]");

				uint8[] so = new .[17]; // oops, wrong size
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			{
				// Infer size to be 5

				uint8[] s = scope .(12, 24, 53, 34, 5);

				uint8[] so = null;
				Test.Assert((Bon.Deserialize(ref so, "[12,24,53,34,5]") case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			{
				// Add array type to lookup for the deserialize call to find it
				gBonEnv.RegisterPolyType!(typeof(uint8[]));

				Object s = scope uint8[](12, 24, 53, 34, 5, 0, 0);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "(uint8[])<7>[12,24,53,34,5]");

				Object so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && s.GetType() == so.GetType());
				delete so;
			}

			{
				uint8[] s = scope .(12, 24, 53, 34, 5, 0, 0);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<7>[12,24,53,34,5]");

				uint8[] so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			{
				uint16[,] s = scope .[2,2]((532, 332), (224, 2896));
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<2,2>[[532,332],[224,2896]]");

				uint16[,] so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			{
				uint16[,,] s = scope .[2,5,1](((1), (2), (3), (4), (5)), ((20), (21), (22), (23), (24)));
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<2,5,1>[[[1],[2],[3],[4],[5]],[[20],[21],[22],[23],[24]]]");

				uint16[,,] so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			{
				uint64[,,,] s = scope .[1,2,3,4]();
				s[0,1,0,3] = 1646;
				s[0,0,0,0] = 5000;
				s[0,0,2,1] = 9090;

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<1,2,3,4>[[[[5000],?,[?,9090]],[[?,?,?,1646],?]]]");

				uint64[,,,] so = null;
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
				delete so;
			}

			using (PushDeFlags(.IgnoreUnmentionedValues))
			{
				uint64[,,,] s = scope .[1,2,3,4]();
				s[0,1,0,3] = 1646;
				s[0,0,0,0] = 5000;
				s[0,0,2,1] = 9090;

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<1,2,3,4>[[[[5000],?,[?,9090]],[[?,?,?,1646],?]]]");

				uint64[,,,] so = scope .[1,2,3,4]();
				so[0,1,1,1] = 50;
				so[0,1,0,0] = 60;
				so[0,1,2,0] = 70;

				Test.Assert((Bon.Deserialize(ref so, str) case .Ok)
					&& s[0,1,0,3] == so[0,1,0,3] // Fill mentioned values
					&& s[0,0,0,0] == so[0,0,0,0]
					&& s[0,0,2,1] == so[0,0,2,1]
					&& so[0,1,1,1] == 50 // Ignore unmentioned
					&& so[0,1,0,0] == 60
					&& so[0,1,2,0] == 70);
			}

			{
				uint16[,,] so = null;
				Test.Assert(Bon.Deserialize(ref so, "<2,5,1>[[[1],[2],[3],[4],[5]],[[20],[21],[22],[23],[24],[]]]") case .Err);
				delete so;
			}

			{
				uint16[,,] so = null;
				Test.Assert(Bon.Deserialize(ref so, "<2,5>") case .Err);
				delete so;
			}

			{
				uint16[,,] so = null;
				Test.Assert(Bon.Deserialize(ref so, " < 2,5 , 1 > [[[1],[2],[ 3 ] ,  [ 4 ] ] ] ") case .Ok);
				delete so;
			}

			{
				uint16[,,] so = null;
				Test.Assert(Bon.Deserialize(ref so, "<2,5,") case .Err);
			}

			{
				uint16[,,] so = null;
				Test.Assert(Bon.Deserialize(ref so, "<const 2,5>") case .Err);
			}
		}

		[Test]
		static void Collections()
		{
			{
				let l = scope List<AClass>();
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "<0>[]");

				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && l.Count == lo.Count);
				delete lo;
			}

			{
				let l = scope List<AClass>();
				l.Add(scope AClass() { aStringThing = new $"uhh", thing = 255, data = .{ time=1, value=10 } });
				l.Add(scope AClass() { aStringThing = new $"Hi, na?", thing = 42 });
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "<2>[{aStringThing=\"uhh\",thing=255,data={time=1,value=10}},{aStringThing=\"Hi, na?\",thing=42}]");

				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && l.Count == lo.Count && l[0].aStringThing == lo[0].aStringThing);
				DeleteContainerAndItems!(lo);
			}

			{
				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, "[{aStringThing=\"uhh\",thing=255,data={time=1,value=10}},{aStringThing=\"Hi, na?\",thing=42}]") case .Ok) && lo.Count == 2);
				DeleteContainerAndItems!(lo);
			}

			{
				let l = scope List<int32>()
					{
						1, 2, 3, 8, 9, 10, 100, 1000, 10000, 0, 0
					};
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "<11>[1,2,3,8,9,10,100,1000,10000]");

				List<int32> lo = scope List<int32>()
					{
						2, 3, 4, 5, 6, 100, 200, 300, 400, 500, 1000, 2500, 8000, 10000 // oops, already in use
					};
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && ArrayEqual!(l, lo));
			}
		}

		[Serializable]
		struct Compat
		{
			public uint version;
		}

		[Test]
		static void FileLevel()
		{
			SetupStringHandler!();

			{
				let s = StructB() {
					age = 23,
					type = .OtherThing,
					name = "nice name"
				};
				let sv = Compat() {
					version = 1
				};

				let str = Bon.Serialize(sv, .. scope .());
				Bon.Serialize(s, str);
				Test.Assert(str == "{version=1},{name=\"nice name\",age=23,type=1}");

				Compat svo = ?;
				StructB so = ?;

				switch (Bon.Deserialize(ref svo, str))
				{
				case .Err:
					Test.FatalError();
				case .Ok(let con):

					Test.Assert(svo == sv);

					Test.Assert((Bon.Deserialize(ref so, con) case .Ok) && so == s);
				}
			}

			{
				let s = StructB() {
					age = 23,
					type = .OtherThing,
					name = "nice name"
				};
				let sv = Compat();

				let str = Bon.Serialize(sv, .. scope .());
				Bon.Serialize(s, str);
				Test.Assert(str == "?,{name=\"nice name\",age=23,type=1}");

				Compat svo = ?;
				StructB so = ?;

				switch (Bon.Deserialize(ref svo, str))
				{
				case .Err:
					Test.FatalError();
				case .Ok(let con):

					Test.Assert(svo == sv);

					Test.Assert((Bon.Deserialize(ref so, con) case .Ok) && so == s);
				}
			}

			{
				StructB so = ?;
				Test.Assert((Bon.Deserialize(ref so, "{name=$[{},\n{age=325}],age=23,type=1}") case .Ok) && so.name == "{},\n{age=325}");
			}

			{
				StructB so = ?;

				let c = BonContext("[14,362,12],{lalala},{name=$[{},\n{age=325}],age=23,type=1}");
				Test.Assert(c.GetEntryCount() == 3);
				Test.Assert(c.SkipEntry(2) case .Ok(let skipped));
				Test.Assert((Bon.Deserialize(ref so, skipped) case .Ok(let empty)) && so.name == "{},\n{age=325}");
				Test.Assert(empty.Rewind() == c);
			}
		}

		// TODO: test arrays & collections for [Align()]

		[Test]
		static void Pointers()
		{
			// These tests mostly assert how pointers *dont* work right now
			// We might support them in limited way at some point...

			// This only works because the pointer is a file-level entry
			// that is null
			{
				uint8* p = null;
				let str = Bon.Serialize(p, .. scope .());
				Test.Assert(str == "?");

				uint8* po = null;
				Test.Assert(Bon.Deserialize(ref po, str) case .Ok);
			}

			{
				uint8 number = 44;
				uint8* p = &number;
				let str = Bon.Serialize(p, .. scope .());
				Test.Assert(str == "");

				{
					uint8* po = null;
					Test.Assert(Bon.Deserialize(ref po, str) case .Err);
				}
			}

			// Explicitly mentioned pointers always error
			{
				uint8* po = null;
				Test.Assert(Bon.Deserialize(ref po, "d") case .Err);
			}

			{
				uint8*[4] po = .();
				Test.Assert(Bon.Deserialize(ref po, "[]") case .Ok);
			}

			{
				uint8 d = 0;
				uint8*[4] po = .(&d,&d,&d,&d); // Cannot null pointers
				Test.Assert(Bon.Deserialize(ref po, "[]") case .Err);
			}

			using (PushDeFlags(.IgnorePointers))
			{
				uint8 d = 0;
				uint8*[4] po = .(&d,&d,&d,&d);
				uint8*[4] poc = po;
				Test.Assert((Bon.Deserialize(ref po, "[]") case .Ok)
					&& po == poc); // But nothing actually changed
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
			Test.Assert(Bon.Deserialize(ref i, " \n\t") case .Err);

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
			Test.Assert(Bon.Deserialize(ref d, "{?}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{time=?}") case .Err);
			Test.Assert(Bon.Deserialize(ref d, "{timedd=}") case .Err);
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
			
			Test.Assert(Bon.Deserialize(ref a, "<const12>[]\n\n") case .Ok); // There is no reason for this to work, but also none for it to not work
			Test.Assert(Bon.Deserialize(ref a, "<1>[]") case .Ok);
			Test.Assert(Bon.Deserialize(ref a, "[?, ?],blahblah") case .Ok); // Only checks current entry...
		}
	}
}
