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

		static StringView HandleStringView(StringView view)
		{
			// Since we're dealing with const strings,
			// just intern the deserialized views to get
			// back the exact string literal
			return view.Intern();
		}

		static delegate StringView(StringView) stringViewHandler = new => HandleStringView;
		static List<String> strings = new .() ~ DeleteContainerAndItems!(_);

		static void MakeString(ValueView val)
		{
			var str = strings.Add(.. new .());

			val.Assign(str);
		}

		static mixin SetupStringHandler()
		{
			gBonEnv.stringViewHandler = stringViewHandler;

			if (!gBonEnv.allocHandlers.ContainsKey(typeof(String)))
				gBonEnv.allocHandlers.Add(typeof(String), (.)new => MakeString);
		}

		static mixin NoStringHandler()
		{
			gBonEnv.stringViewHandler = stringViewHandler;
			if (gBonEnv.allocHandlers.GetAndRemove(typeof(String)) case .Ok(let pair))
				delete pair.value;
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
				Test.Assert(str == "true");

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
				float f = 1;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "1");

				float of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				double f = 1;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "1");

				double of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				double f = double.NaN;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "NaN");

				double of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				float f = float.PositiveInfinity;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "Infinity");

				float of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				float f = 1e4f;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "10000");

				float of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				double f = -1e-8;
				let str = Bon.Serialize(f, .. scope .());
				Test.Assert(str == "-1e-08");

				double of = ?;
				Test.Assert((Bon.Deserialize(ref of, str) case .Ok) && of == f);
			}

			{
				double of = ?;
				Test.Assert((Bon.Deserialize(ref of, "-1E-08") case .Ok) && of == -1E-08);
			}

			{
				float of = ?;
				Test.Assert((Bon.Deserialize(ref of, "+infinity") case .Ok) && of == float.PositiveInfinity);
			}

			{
				float of = ?;
				Test.Assert((Bon.Deserialize(ref of, "nan") case .Ok) && of == float.NaN);
			}

			{
				float ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, "1f") case .Ok) && ob == 1f);
			}

			{
				float ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, "0.1") case .Ok) && ob == 0.1f);
			}

			{
				float ob = ?;
				Test.Assert((Bon.Deserialize(ref ob, ".1") case .Ok) && ob == 0.1f);
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
				int i = ?;
				Test.Assert((Bon.Deserialize(ref i, "+0xF5aL") case .Ok) && i == 3930);
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
				int i = ?;
				Test.Assert((Bon.Deserialize(ref i, "+00000") case .Ok) && i == 0);
			}

			{
				uint8 i = ?;
				Test.Assert((Bon.Deserialize(ref i, "00000160") case .Ok) && i == 160);
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

			{
				int8 oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, "-0x'L") case .Ok) && oi == 0); // This makes NO sense, but beef allows it too
			}

			// Should error (but not crash)

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "++Infinity") case .Err);
			}

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "-NaN") case .Err);
			}

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "0.0.") case .Err);
			}

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "0-1") case .Err);
			}

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "5e") case .Err);
			}

			{
				float ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "5e-03999999999") case .Err);
			}

			{
				double ob = ?;
				Test.Assert(Bon.Deserialize(ref ob, "e-10") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "299") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "-25u") case .Err);
			}

			{
				uint8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "-25") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "0b2") case .Err);
			}

			{
				int8 oi = ?;
				Test.Assert(Bon.Deserialize(ref oi, "00b0") case .Err);
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

		[BonTarget]
		enum TypeB : uint16
		{
			AThing,
			OtherThing,
			Count
		}

		[BonTarget]
		enum SomeValues
		{
			public const SomeValues defaultOption = .Option2;

			case Option1;
			case Option2;
			case Option3;
		}

		[BonTarget]
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

		[BonTarget,BonPolyRegister] // Also used for boxing tests
		enum SomeTokens : char8
		{
			Dot = '.',
			Slash = '/',
			Dash = '-'
		}

		[Test]
		static void Enums()
		{
			// No reflection data and not verbose
			{
				TypeA i = .Named120;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "120");

				TypeA oi = ?;
				Test.Assert((Bon.Deserialize(ref oi, str) case .Ok) && oi == i);
			}

			// No reflection data but Serialize uses typeof(EnumT) which includes reflection...
			using (PushFlags(.Verbose))
			{
				TypeA i = .Named120;
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".Named120");

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

		[BonTarget,Ordered]
		struct SomeThings
		{
			public int i;
			public float f;
			public String str;

			uint8 intern;

			[BonInclude]
			uint16 important;

			[BonIgnore]
			public uint dont;

			public int8 n;
		}

		[BonTarget]
		struct StructA
		{
			public int thing;
			public StructB[5] bs;
		}

		[BonTarget]
		struct StructB
		{
			public StringView name;
			public uint8 age;
			public TypeB type;
		}

		[BonTarget,BonPolyRegister] // Also use it for boxing tests
		struct SomeData : IThing
		{
			public double time;
			public uint64 value;
		}

		[BonTarget, BonKeepMembersUnlessSet]
		struct OldConfig
		{
			public bool fullscreen = true;
		}

		[BonTarget, BonKeepMembersUnlessSet]
		struct Config
		{
			public bool fullscreen = true;
			public float zoom = 1;
			public int difficulty = 2;
		}

		[BonTarget]
		struct Retain
		{
			public uint8 num;
			public Config config;

			public RetainInner retain1;

			[BonKeepUnlessSet]
			public RetainInner retain2;

			[BonIgnore]
			public int intern;

			[BonArrayKeepUnlessSet]
			public int8[2] pair; // Retain everything!

			[BonKeepUnlessSet]
			public int8[] data; // Full array would be set, otherwise everything is kept (just considers reference)

			[BonArrayKeepUnlessSet]
			public uint8 nope;
		}

		[BonTarget]
		struct RetainInner
		{
			public uint8 num;

			[BonKeepUnlessSet]
			public bool retain;

			[BonIgnore]
			public int intern;
		}

		struct NoData
		{
			public int a;
		}

		[Test]
		static void Structs()
		{
			SetupStringHandler!();

			using (PushFlags(.Verbose))
			{
				let s = NoData() { a = 25 };
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{}/* No reflection data for Bon.Tests.NoData. Add [BonTarget] or force it */");

				NoData so = default;
				Test.Assert(Bon.Deserialize(ref so, "{a=25}") case .Err);
			}

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
					SomeThings so = default;
					so.str = scope .();
					Test.Assert(Bon.Deserialize(ref so, "default") case .Err);
				}

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
					Test.Assert(Bon.Deserialize(ref so, str) case .Err);
				}

				using (PushFlags(.IncludeDefault))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",important=32656,n=0}");

					SomeThings so = default; // All of these need to be nulled so that the string pointer is not pointing somewhere random!
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && Bon.Serialize(so, .. scope .()) == str);
				}

				using (PushFlags(.IgnorePermissions))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656,dont=8}");

					// We cannot access dont
					SomeThings so = default;
					Test.Assert(Bon.Deserialize(ref so, str) case .Err);
				}

				using (PushFlags(.IncludeNonPublic|.IgnorePermissions|.IncludeDefault))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == "{i=5,f=1,str=\"oh hello\",intern=54,important=32656,dont=8,n=0}");

					// We cannot access dont and intern
					SomeThings so = default;
					Test.Assert(Bon.Deserialize(ref so, str) case .Err);
					Test.Assert(Bon.Deserialize(ref so, "{i=5,f=1,str=\"oh hello\",important=32656,n=0}") case .Ok);
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
					Test.Assert(str == "{thing=651,bs=[{name=\"first element\",age=34,type=1},{name=\"second element\",age=101},{name=null},{name=\"\"},{name=null}]}");

					StructA so = default;
					Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && s == so);
				}

				using (PushFlags(.Verbose))
				{
					let str = Bon.Serialize(s, .. scope .());
					Test.Assert(str == """
						{
							thing = 651,
							bs = <const 5>[
								{
									name = "first element",
									age = 34,
									type = .OtherThing
								},
								{
									name = "second element",
									age = 101
								},
								{
									name = null
								},
								{
									name = ""
								},
								{
									name = null
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

			{
				var s = SomeData();
				Test.Assert(Bon.Deserialize(ref s, "{time=?}") case .Ok);
			}

			// Upgrade old configs
			{
				let s = OldConfig { fullscreen = false }; // Old version where there was only fullscreen
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{fullscreen=0}");

				var so = Config(); // Newer defaults
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok)
					&& so.fullscreen == false // Applied
					&& so.difficulty == 2 && so.zoom == 1); // Newer (thus not explicitly set) values kept!

				let str2 = Bon.Serialize(so, .. scope .());
				Test.Assert(str2 == "{fullscreen=0,zoom=1,difficulty=2}");
			}

			{
				let s = Retain() {
					num = 5,
					config = .() {
						fullscreen = true,
						zoom = 4,
						difficulty = 0
					},
					retain1 = .() {
						num = 6,
						retain = true,
						intern = 10
					},
					retain2 = .() {
						num = 7,
						retain = true,
						intern = 100
					},
					intern = 1000,
					pair = .(2, 4),
					data = scope:: .(1, 2, 3, 4, 5),
					nope = 42
				};

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{num=5,config={fullscreen=1,zoom=4,difficulty=0},retain1={num=6,retain=1},retain2={num=7,retain=1},pair=[2,4],data=[1,2,3,4,5],nope=42}");

				{
					var so = s;
					var st = s;
					st.num = 60;
					st.retain1.num = 0;
					st.nope = 0;
					Test.Assert((Bon.Deserialize(ref so, "{num=60}") case .Ok) && so == st);
				}

				{
					var so = s;
					var st = s;
					st.num = 60;
					st.retain1.num = 0;
					st.nope = 0;
					Test.Assert((Bon.Deserialize(ref so, "{num=60,retain1=?,retain2=?,data=?,pair=?}") case .Ok) && so == st);
				}

				{
					var so = s;
					var st = s;
					st.num = 0;
					st.retain1.num = 4;
					st.retain2.retain = false;
					st.retain2.num = 0;
					st.pair = .(2, 2);
					st.data = scope .(0, 1, 0, 6, 0);
					st.nope = 0;

					let str2 = Bon.Serialize(st, .. scope .());
					Test.Assert(str2 == "{config={fullscreen=1,zoom=4,difficulty=0},retain1={num=4,retain=1},retain2={retain=0},pair=[2,2],data=<5>[?,1,?,6]}");

					Test.Assert(Bon.Deserialize(ref so, "{num=0,pair=[?,2],retain1={num=4},retain2={retain=false},data=<5>[0, 1, ?, 6]}") case .Ok);
					Test.Assert(ArrayEqual!(so.data, st.data)); // @report removing st.data and typing "st." crashes
					st.data = so.data = null;
					Test.Assert(st == so);

				}

				{
					var so = s;
					var st = s;
					st.num = 0;
					st.config.zoom = 16;
					st.retain1.num = 0;
					st.retain1.retain = false;
					st.retain2.num = 0;
					st.retain2.retain = false;
					st.pair = .(0, 4);
					st.nope = 0;
					Test.Assert((Bon.Deserialize(ref so, "{pair=[default, ?],retain1=default,retain2=default,config={zoom=16}}") case .Ok) && so == st);
				}

				{
					var so = s;
					so.data = null;
					var st = so;
					st.num = 0;
					st.retain1.num = 0;
					st.retain2.num = 0;
					st.data = scope .(0 , 4);
					st.nope = 0;
					Test.Assert(Bon.Deserialize(ref so, "{data=[00, 04],retain2={}}") case .Ok);
					Test.Assert(ArrayEqual!(so.data, st.data));
					delete so.data;
					st.data = so.data = null;
					Test.Assert(st == so);
				}

				{
					var so = s;
					so.data = null;
					var st = so;
					st.num = 0;
					st.config = default;
					st.retain1.num = 0;
					st.retain1.retain = false;
					st.retain2.num = 0;
					st.retain2.retain = false;
					st.pair = default;
					st.nope = 0;
					Test.Assert((Bon.Deserialize(ref so, "default") case .Ok) && so == st);
				}

				{
					var so = s;
					Test.Assert(Bon.Deserialize(ref so, "{retain1={intern=2}}") case .Err);
					Test.Assert(Bon.Deserialize(ref so, "{data=null}") case .Err);
					Test.Assert(Bon.Deserialize(ref so, "default") case .Err);
				}
			}
		}

		[BonTarget]
		struct Vector2 : this(float x, float y);

		[BonTarget, BonPolyRegister]
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

		enum CarryIndicrect
		{
			case One(int);
			case Two(String);
			case Three(uint8[]);
		}

		[BonTarget]
		struct Indirect
		{
			public CarryIndicrect carry;
			public Thing thing;
		}

		[Test]
		static void EnumUnions()
		{
			// No reflection data but Serialize uses typeof(EnumT) which includes reflection...
			using (PushFlags(.IncludeDefault))
			{
				Carry i = .One(1);
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == ".One{0=1}");

				Carry si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si == i);
			}

			{
				Indirect i = .() { carry = .One(1), thing = .Circle(.(1, 16), 1) };
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == "{carry=?,thing=.Circle{pos={x=1,y=16},radius=1}}");

				Indirect siu = ?;
				Test.Assert(Bon.Deserialize(ref siu, str) case .Err);

				Indirect si = default;
				Test.Assert((Bon.Deserialize(ref si, str) case .Ok) && si.carry == default);
				Test.Assert((Bon.Deserialize(ref si,"{carry=.One{0=1}}") case .Err) && si.carry == default);
			}

			using (PushFlags(.Verbose))
			{
				Indirect i = .() { carry = .One(1)};
				let str = Bon.Serialize(i, .. scope .());
				Test.Assert(str == """
					{
						carry = ?/* No reflection data for Bon.Tests.CarryIndicrect. Add [BonTarget] or force it */,
						thing = .Nothing{}
					}
					""");

				Indirect siu = i;
				Test.Assert(Bon.Deserialize(ref siu, str) case .Err);
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
				Test.Assert(str == ".Circle{pos={},radius=4.5}");

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
				SetupStringHandler!();

				Thing i = .Text(.(50, 50), "Something\"!", 24, 90f);
				Test.Assert(Bon.Deserialize(ref i, "?") case .Err);
			}

			{
				SetupStringHandler!();

				Thing i = .Text(.(50, 50), "Something\"!", 24, 90f);
				Test.Assert(Bon.Deserialize(ref i, ".Text{size=3}") case .Err);
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
						pos = {
							x = 10,
							y = 1
						},
						radius = 4.5
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
				gBonEnv.RegisterPolyType!(typeof(Int));

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

				Object oi = scope box SomeTokens.Dash; // oops- wrong type
				Test.Assert(Bon.Deserialize(ref oi, str) case .Err);
			}
		}

		[BonTarget,BonPolyRegister]
		class AClass
		{
			public String aStringThing ~ if (_ != null) delete _;
			public uint8 thing;
			public SomeData data;
		}

		[BonTarget] // Base classes also need to be marked!
		abstract class BaseThing
		{
			public abstract int Number { get; set; }

			public String Name = new .("nothing") ~ delete _;
		}

		[BonTarget]
		class SaveFile
		{
			public int kills;

			[BonKeepUnlessSet]
			public String Name = new .(8) ~ delete _;
		}

		interface IThing
		{

		}

		[BonTarget,BonPolyRegister]
		class OtherClassThing : BaseThing, IThing
		{
			public uint32 something;

			public override int Number { get; set; }
		}

		[BonTarget]
		class FinClass : OtherClassThing
		{
			public new uint64 something;
		}

		[BonTarget,BonPolyRegister]
		class LookAThing<T>
		{
			[BonInclude]
			T tThingLook;
		}

		[BonTarget,BonPolyRegister]
		class Unmentioned
		{
			public int a;
		}

		[Test]
		static void Classes()
		{
			NoStringHandler!();

			{
				Object co = null;
				Test.Assert(Bon.Deserialize(ref co, "(Bon.Tests.Unmentioned){a=15}") case .Ok);
				delete co;
			}

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
			}

			using (PushFlags(.IncludeNonPublic))
			{
				Object c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,prop__Number=59992,Name=\"nothing\"}");

				Object co = new AClass(); // oops.. wrong type there!
				Test.Assert(Bon.Deserialize(ref co, str) case .Err);
				delete co;
			}

			{
				BaseThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,Name=\"nothing\"}");

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

			{
				SaveFile c = scope .();
				c.kills = 12;
				DeleteAndNullify!(c.Name); // Can still be null and will be explicitly noted as such

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "{kills=12,Name=null}");

				SaveFile co = scope .();
				Test.Assert((Bon.Deserialize(ref co, "{kills=12}") case .Ok) // This is an old version of the save file, pretend Name doesnt exitst yet..
					&& co.kills == c.kills // Set thing is applied
					&& co.Name != null);

				// Name reference is kept, since Name (which "didn't exist" thus wasn't explicitly set to null),
				// loads old file into expanded layout correctly without trying to null Name!
				
				let str2 = Bon.Serialize(co, .. scope .());
				Test.Assert(str2 == "{kills=12,Name=\"\"}");
			}
		}

		[Test]
		static void Interfaces()
		{
			NoStringHandler!();

			using (PushFlags(.IncludeNonPublic))
			{
				IThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,prop__Number=59992,Name=\"nothing\"}");

				IThing co = null;
				Test.Assert(Bon.Deserialize(ref co, str) case .Err);
				delete co;
			}

			{
				IThing c = scope OtherClassThing() { Number = 59992, something = 222252222 };

				let str = Bon.Serialize(c, .. scope .());
				Test.Assert(str == "(Bon.Tests.OtherClassThing){something=222252222,Name=\"nothing\"}");

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

		[Align(8),CRepr,BonTarget]
		struct AlignStruct
		{
			public uint16 a;
			public uint8 b;
		}

		[BonTarget]
		struct NormalArray
		{
			public uint64[,,,] data;
			public List<int32> listData;
			public Dictionary<int,uint8> dictData;
		}

		[BonTarget]
		struct PatchableArray
		{
			[BonArrayKeepUnlessSet]
			public uint64[,,,] data;
			
			[BonArrayKeepUnlessSet]
			public List<int32> listData;

			[BonArrayKeepUnlessSet]
			public Dictionary<int,uint8> dictData;
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
				Test.Assert((Bon.Deserialize(ref so, "[]") case .Ok) && so.Count == 0);
				delete so;
				so = null;
				
				Test.Assert(Bon.Deserialize(ref so, "[,]") case .Err);
			}

			{
				uint8[] s = scope .(12, 24, 53, 34, 5, 0, 0);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<7>[12,24,53,34,5]");

				uint8[] so = scope .[7];
				Test.Assert((Bon.Deserialize(ref so, str) case .Ok) && ArrayEqual!(s, so));
			}

			{
				uint8[] s = scope .(12, 24, 53, 34, 5);
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "[12,24,53,34,5]");

				uint8[] so = scope .[17]; // oops, wrong size
				Test.Assert(Bon.Deserialize(ref so, str) case .Err);
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
				AlignStruct[,] s = scope .[2,2]((.{a=5,b=16}, .{a=10,b=64}), (default, .{a=100,b=255}));
				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "<2,2>[[{a=5,b=16},{a=10,b=64}],[{},{a=100,b=255}]]");

				AlignStruct[,] so = null;
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

			{
				NormalArray s = .() { data = scope .[1,2,3,4]() };
				s.data[0,1,0,3] = 1646;
				s.data[0,0,0,0] = 5000;
				s.data[0,0,2,1] = 9090;

				let str = Bon.Serialize(s, .. scope .());
				Test.Assert(str == "{data=<1,2,3,4>[[[[5000],?,[?,9090]],[[?,?,?,1646],?]]]}");

				PatchableArray so = .() { data = scope .[1,2,3,4]() };
				so.data[0,1,1,1] = 50;
				so.data[0,1,0,0] = 60;
				so.data[0,1,2,0] = 70;

				Test.Assert((Bon.Deserialize(ref so, str) case .Ok)
					&& s.data[0,1,0,3] == so.data[0,1,0,3] // Fill mentioned values
					&& s.data[0,0,0,0] == so.data[0,0,0,0]
					&& s.data[0,0,2,1] == so.data[0,0,2,1]
					&& so.data[0,1,1,1] == 50 // Kept
					&& so.data[0,1,0,0] == 60
					&& so.data[0,1,2,0] == 70);

				let str2 = Bon.Serialize(so, .. scope .());
				Test.Assert(str2 == "{data=<1,2,3,4>[[[[5000,0,0,0],[0,0,0,0],[0,9090,0,0]],[[60,0,0,1646],[0,50,0,0],[70,0,0,0]]]]}");
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
				Test.Assert(Bon.Deserialize(ref so, " < 2,5 , 1 > [[[1],[2],[ 3 ] ,  [ 4 ], ] , ] ") case .Ok);
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
		static void List()
		{
			NoStringHandler!();

			{
				let l = scope List<AClass>();
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "[]");

				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && l.Count == lo.Count);
				delete lo;
			}

			{
				let l = scope List<AClass>();
				l.Add(scope AClass() { aStringThing = new $"uhh", thing = 255, data = .{ time=1, value=10 } });
				l.Add(scope AClass() { aStringThing = new $"Hi, na?", thing = 42 });
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "[{aStringThing=\"uhh\",thing=255,data={time=1,value=10}},{aStringThing=\"Hi, na?\",thing=42,data={}}]");

				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && l.Count == lo.Count && l[0].aStringThing == lo[0].aStringThing);
				DeleteContainerAndItems!(lo);
			}

			{
				var l = scope List<AClass>();
				l.Add(scope AClass() { aStringThing = new $"uhh", thing = 255, data = .{ time=1, value=10 } });
				l.Add(scope AClass() { aStringThing = new $"Hi, na?", thing = 42 });

				// Setting the first value is fine, but since we shrink the array here
				// we'd leak the second element, which should error!
				Test.Assert(Bon.Deserialize(ref l, "[{aStringThing=\"Hi, na?\",thing=42}]") case .Err);
			}

			{
				List<AClass> lo = null;
				Test.Assert((Bon.Deserialize(ref lo, "[{aStringThing=\"uhh\",thing=255,data={time=1,value=10}},{aStringThing=\"Hi, na?\",thing=42},]") case .Ok) && lo.Count == 2);
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

			{
				let l = NormalArray { listData = scope List<int32>()
					{
						1, 2, 3, 8, 9, 10, 100, 1000, 10000, 0, 0
					}};
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "{listData=<11>[1,2,3,8,9,10,100,1000,10000]}");

				var lo = PatchableArray { listData = scope List<int32>()
					{
						2, 3, 4, 5, 6, 100, 200, 300, 400, 500, 1000, 2500, 8000, 10000, 0, 1, 0 // oops, already in use
					}};
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && lo.listData.Count == 17 && lo.listData[5] == l.listData[5] && lo.listData[10] == 1000);

				let str2 = Bon.Serialize(lo, .. scope .());
				Test.Assert(str2 == "{listData=[1,2,3,8,9,10,100,1000,10000,500,1000,2500,8000,10000,0,1,0]}");
			}

			{
				let l = scope List<AlignStruct>()
					{
						AlignStruct{a=1,b=2}, AlignStruct{}, AlignStruct{a=12,b=150}
					};
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "[{a=1,b=2},{},{a=12,b=150}]");

				List<AlignStruct> lo = scope List<AlignStruct>()
					{
						AlignStruct{}, AlignStruct{}, AlignStruct{}, AlignStruct{a=10,b=12} // oops, already in use
					};
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && ArrayEqual!(l, lo));
			}

			{
				let l = scope List<AlignStruct>(3)
					{
						AlignStruct{a=1,b=2}, AlignStruct{}, AlignStruct{a=12,b=150}
					};
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "[{a=1,b=2},{},{a=12,b=150}]");

				List<AlignStruct> lo = scope List<AlignStruct>(3);
				Test.Assert((Bon.Deserialize(ref lo, str) case .Ok) && ArrayEqual!(l, lo));
			}

			{
				gBonEnv.RegisterPolyType!(typeof(List<int32>));
				Object l = scope List<int32>(11)
					{
						1, 2, 3, 8, 9, 10, 100, 1000, 10000, 0, 0
					};
				let str = Bon.Serialize(l, .. scope .());
				Test.Assert(str == "(System.Collections.List<int32>)<11>[1,2,3,8,9,10,100,1000,10000]");

				Object lo = scope List<int32>(14)
					{
						2, 3, 4, 5, 6, 100, 200, 300, 400, 500, 1000, 2500, 8000, 10000 // oops, already in use
					};
				Test.Assert(Bon.Deserialize(ref lo, str) case .Ok);
			}
		}

		[BonTarget]
		struct HashStruct : IHashable
		{
			public int a;
			public int b;

			public int GetHashCode()
			{
				return a + b;
			}
		}

		[Test]
		static void Dictionary()
		{
			SetupStringHandler!();

			{
				Dictionary<int,uint8> d = scope .(2);
				d.Add(150, 2);
				d.Add(24, 23);

				{
					let str = Bon.Serialize(d, .. scope .());
					Test.Assert(str == "[150:2,24:23]");

					{
						Dictionary<int,uint8> o = scope .();
						Test.Assert((Bon.Deserialize(ref o, str) case .Ok)
							&& d[150] == o[150] && d[24] == o[24]);
					}

					{
						Dictionary<int,uint8> o = null;
						Test.Assert((Bon.Deserialize(ref o, str) case .Ok)
							&& d[150] == o[150] && d[24] == o[24]);
						delete o;
					}

					{
						Dictionary<int,uint8> o = scope .(3);
						o.Add(150, 200);
						o.Add(234, 1);
						o.Add(6000, 1);

						Test.Assert((Bon.Deserialize(ref o, str) case .Ok)
							&& d[150] == o[150] && d[24] == o[24] && o.Count == 2);
					}

					{
						let s = NormalArray() { dictData = d };
						let str2 = Bon.Serialize(s, .. scope .());
						Test.Assert(str2 == "{dictData=[150:2,24:23]}");

						var o = PatchableArray() { dictData =scope .(3) };
						o.dictData.Add(150, 200);
						o.dictData.Add(234, 1);
						o.dictData.Add(6000, 1);

						Test.Assert((Bon.Deserialize(ref o, str2) case .Ok)
							&& s.dictData[150] == o.dictData[150] && s.dictData[24] == o.dictData[24]
							&& o.dictData[234] == 1 && o.dictData[6000] == 1 && o.dictData.Count == 4);

						let str3 = Bon.Serialize(o, .. scope .());
						Test.Assert(str3 == "{dictData=[150:2,234:1,6000:1,24:23]}");
					}
				}

				using (PushFlags(.Verbose))
				{
					let str = Bon.Serialize(d, .. scope .());
					Test.Assert(str == """
						[
							150: 2,
							24: 23
						]
						""");

					Dictionary<int,uint8> o = scope .(2);
					Test.Assert((Bon.Deserialize(ref o, str) case .Ok)
						&& d[150] == o[150] && d[24] == o[24]);
				}
			}

			{
				Dictionary<String,SomeData> d = scope .(2);
				d.Add("oneThing", SomeData{ value = 5, time = 0 });
				d.Add("a_string", SomeData{ value = 1700, time = 2f});

				let str = Bon.Serialize(d, .. scope .());
				Test.Assert(str == "[\"oneThing\":{value=5},\"a_string\":{time=2,value=1700}]");

				{
					Dictionary<String,SomeData> o = scope .(2);
					Test.Assert((Bon.Deserialize(ref o, str) case .Ok) && d["oneThing"] == o["oneThing"] && d["a_string"] == o["a_string"] && o.Count == 2);
				}

				{
					Dictionary<String,SomeData> o = scope .(2);
					o.Add("b", default);

					Test.Assert(Bon.Deserialize(ref o, str) case .Err);
				}
			}

			{
				Dictionary<String,SomeData> o = scope .(2);

				Test.Assert(Bon.Deserialize(ref o, """
					[
						"SomeSTRING!": default,
						"other": {},
						"SomeSTRING!": {}
					]
					""") case .Err);
			}

			{
				Dictionary<HashStruct,SomeData> d = scope .(2);
				d.Add(HashStruct{ a = 120, b = 6000 }, SomeData{ value = 5, time = 0 });
				d.Add(HashStruct{ a = 155, b = 240 }, SomeData{ value = 1700, time = 2f});

				{
					let str = Bon.Serialize(d, .. scope .());
					Test.Assert(str == "[{a=120,b=6000}:{value=5},{a=155,b=240}:{time=2,value=1700}]");

					Dictionary<HashStruct,SomeData> o = scope .(2);
					Test.Assert((Bon.Deserialize(ref o, str) case .Ok) && o.Count == 2
						&& o[HashStruct{ a = 120, b = 6000 }] == SomeData{ value = 5, time = 0 }
						&& o[HashStruct{ a = 155, b = 240 }] == SomeData{ value = 1700, time = 2f});
				}

				using (PushFlags(.Verbose))
				{
					let str = Bon.Serialize(d, .. scope .());
					Test.Assert(str == """
						[
							{
								a = 120,
								b = 6000
							}: {
								value = 5
							},
							{
								a = 155,
								b = 240
							}: {
								time = 2,
								value = 1700
							}
						]
						""");
				}
			}

			{
				Dictionary<String,String> d = scope .(2);
				d.Add("no", "yes");
				d.Add("bad", "good");

				let str = Bon.Serialize(d, .. scope .());
				Test.Assert(str == "[\"no\":\"yes\",\"bad\":\"good\"]");

				Dictionary<String,String> o = scope .(2);
				Test.Assert((Bon.Deserialize(ref o, str) case .Ok) && o.Count == 2
					&& o["no"] == "yes"
					&& o["bad"] == "good");

				Test.Assert(Bon.Deserialize(ref o, "[\"dont\":\"do\"]") case .Err);
			}
		}

		[BonTarget]
		struct Compat
		{
			public uint version;
		}

		[Test]
		static void FileLevel()
		{
			SetupStringHandler!();

			{
				let str = Bon.Serialize(0, .. scope .());
				Bon.Serialize(12, str);
				Bon.Serialize(0, str);
				Bon.Serialize(0, str);
				Test.Assert(str == "?,12,?,?");
			}

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
				Test.Assert(str == "{},{name=\"nice name\",age=23,type=1}");

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
				Test.Assert((Bon.Deserialize(ref so, "{name=$[],age=23,type=1}") case .Ok) && so.name == "");
				Test.Assert(Bon.Deserialize(ref so, "{name=$[/*/**/],age=23,type=1}") case .Err);
				Test.Assert(Bon.Deserialize(ref so, "{name=$[//],age=23,type=1}") case .Err);
				Test.Assert(Bon.Deserialize(ref so, "{name=$[[],age=23,type=1}") case .Err);
				Test.Assert(Bon.Deserialize(ref so, "{name=$[]],age=23,type=1}") case .Err);
				Test.Assert(Bon.Deserialize(ref so, "{name=$[{],age=23,type=1}") case .Err);

				Test.Assert((Bon.Deserialize(ref so, """
					{
						// ]
						/*
						/* ]
						//*/
						*/
						// /*

						name = $[
							{
								name = "]"
								age = 325
							},
							']'
							// ]
							/*
							/* ]
							//*/
							*/
							// /*
						],
						age = 23,
						type = 1
					}
					""") case .Ok) && so.name == """
					{
								name = "]"
								age = 325
							},
							']'
							// ]
							/*
							/* ]
							//*/
							*/
							// /*
					"""); // this formatting is.. slightly weird, but probably doesnt matter. Maybe change?
			}

			{
				StructB so = ?;

				var c = BonContext("[14,362,12],{lalala@\"\\\"},{name=$[/*] // \\'\"*/{} /*] // \\'\"*/,\n{age=325,name=\"}\",c='/*',oop='\\''}],age=23,type=1}");
				Test.Assert(c.GetEntryCount() case .Ok(3));
				Test.Assert(c.SkipEntry(2) case .Ok(let skipped));
				Test.Assert((Bon.Deserialize(ref so, skipped) case .Ok(let empty)) && so.name == "{} /*] // \\'\"*/,\n{age=325,name=\"}\",c='/*',oop='\\''}");
				Test.Assert(empty.Rewind() == c);
				Test.Assert(c.SkipEntry(3) case .Ok(let none));
				Test.Assert(none.SkipEntry(1) case .Err);

				c = BonContext("");
				Test.Assert(c.SkipEntry(1) case .Err);
			}
		}

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
		}

		[Test]
		static void Nullable()
		{
			{
				uint8? number = 44;
				let str = Bon.Serialize(number, .. scope .());
				Test.Assert(str == "44");

				uint8? po = null;
				Test.Assert((Bon.Deserialize(ref po, str) case .Ok) && po == number);
			}

			using (PushFlags(.IncludeDefault))
			{
				uint8? number = null;
				let str = Bon.Serialize(number, .. scope .());
				Test.Assert(str == "null");

				uint8? po = 44;
				Test.Assert((Bon.Deserialize(ref po, str) case .Ok) && po == number);
			}

			{
				SomeData? number = SomeData{ value = 2222 };
				let str = Bon.Serialize(number, .. scope .());
				Test.Assert(str == "{value=2222}");

				SomeData? po = null;
				Test.Assert((Bon.Deserialize(ref po, str) case .Ok) && po == number);
			}
		}

		[Test]
		static void Trash()
		{
			// Just... make sure the constructor doesnt crash
			scope BonEnvironment();

			int i = ?;
			char16 c = ?;
			StringView s = ?;
			SomeValues e = ?;
			SomeData d = ?;
			uint8[2] a = ?;
			SomeData[2] ad = ?;
			Carry eu = ?;

			Test.Assert(Bon.Deserialize(ref eu, ".One{}") case .Err);

			Test.Assert(Bon.Deserialize(ref i, "11 34") case .Err);
			Test.Assert(Bon.Deserialize(ref i, "  11.") case .Err);
			Test.Assert(Bon.Deserialize(ref i, " \n\t") case .Err);
			Test.Assert(Bon.Deserialize(ref i, "") case .Err);

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

//#define PROFILE_TEST
#if PROFILE_TEST		
		[Test]
		static void Profile()
		{
			ProfileInstance profInst = default;
			switch (Profiler.StartSampling("Test"))
			{
			case .Err:
				Test.FatalError("No profiler!");
			case .Ok(let val):
				profInst = val;
			}

			for (let i < 1000)
			{
				Primitives();
				Strings();
				SizedArrays();
				Enums();
				Structs();
				EnumUnions();
				Boxed();
				Classes();
				Interfaces();
				Arrays();
				List();
				Dictionary();
				FileLevel();
				Pointers();
				Nullable();
				Trash();

				ClearAndDeleteItems!(strings);
			}

			profInst.Dispose();
		}
#endif
	}
}
