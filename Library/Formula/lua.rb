class Lua < Formula
  homepage "http://www.lua.org/"
  url "http://www.lua.org/ftp/lua-5.2.3.tar.gz"
  mirror "https://mirrors.kernel.org/debian/pool/main/l/lua5.2/lua5.2_5.2.3.orig.tar.gz"
  sha256 "13c2fb97961381f7d06d5b5cea55b743c163800896fd5c5e2356201d3619002d"
  revision 2

  bottle do
    sha256 "fb2d346b786331f1b71ff793b52274702f9daa3a52c49b336aea4e50bd4232ed" => :yosemite
    sha256 "05f8ad2e915eef8b48ee99e74cc7e451301d2632c1c8494a592e1a42a8880f75" => :mavericks
    sha256 "b334c5254a66b026c1944db77c0cb41f3cd5330575463ec5eb51334c5eb8f68b" => :mountain_lion
  end

  fails_with :llvm do
    build 2326
    cause "Lua itself compiles with LLVM, but may fail when other software tries to link."
  end

  option :universal
  option "with-completion", "Enables advanced readline support"
  option "without-sigaction", "Revert to ANSI signal instead of improved POSIX sigaction"
  option "without-luarocks", "Don't build with Luarocks support embedded"

  # Be sure to build a dylib, or else runtime modules will pull in another static copy of liblua = crashy
  # See: https://github.com/Homebrew/homebrew/pull/5043
  patch :DATA

  # completion provided by advanced readline power patch
  # See http://lua-users.org/wiki/LuaPowerPatches
  if build.with? "completion"
    patch do
      url "http://luajit.org/patches/lua-5.2.0-advanced_readline.patch"
      sha256 "33d32d11fce4f85b88ce8f9bd54e6a6cbea376dfee3dbf8cdda3640e056bc29d"
    end
  end

  # sigaction provided by posix signalling power patch
  if build.with? "sigaction"
    patch do
      url "http://lua-users.org/files/wiki_insecure/power_patches/5.2/lua-5.2.3-sig_catch.patch"
      sha256 "f2e77f73791c08169573658caa3c97ba8b574c870a0a165972ddfbddb948c164"
    end
  end

  resource "luarocks" do
    url "https://github.com/keplerproject/luarocks/archive/v2.2.1.tar.gz"
    sha256 "30e5bd99f82f5e3ea174572c1831f9ff83dfe37727f9fcfc89168b4572193571"
  end

  # Tiger requires an extra header to get off_t on Tiger
  patch do
    url "https://gist.githubusercontent.com/mistydemeo/8e6fdf696a60eeb496ce/raw/9d286fd209728d815a426fb785c31eb1b2638a99/lua-offt.diff"
    sha1 "80b42119163f84a883425afca3139dcf5f2018fb"
  end if MacOS.version < :leopard

  def install
    ENV.universal_binary if build.universal?

    # Use our CC/CFLAGS to compile.
    inreplace "src/Makefile" do |s|
      s.remove_make_var! "CC"
      s.change_make_var! "CFLAGS", "#{ENV.cflags} -DLUA_COMPAT_ALL $(SYSCFLAGS) $(MYCFLAGS)"
      s.change_make_var! "MYLDFLAGS", ENV.ldflags
    end

    # Fix path in the config header
    inreplace "src/luaconf.h", "/usr/local", HOMEBREW_PREFIX

    # We ship our own pkg-config file as Lua no longer provide them upstream.
    system "make", "macosx", "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}"
    system "make", "install", "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}"
    (lib+"pkgconfig/lua.pc").write pc_file

    # Fix some software potentially hunting for different pc names.
    bin.install_symlink "lua" => "lua5.2"
    bin.install_symlink "lua" => "lua-5.2"
    bin.install_symlink "luac" => "luac5.2"
    bin.install_symlink "luac" => "luac-5.2"
    include.install_symlink include => "#{include}/lua5.2"
    (lib/"pkgconfig").install_symlink "lua.pc" => "lua5.2.pc"
    (lib/"pkgconfig").install_symlink "lua.pc" => "lua-5.2.pc"

    # This resource must be handled after the main install, since there's a lua dep.
    # Keeping it in install rather than postinstall means we can bottle.
    if build.with? "luarocks"
      resource("luarocks").stage do
        ENV.prepend_path "PATH", bin

        system "./configure", "--prefix=#{libexec}", "--rocks-tree=#{HOMEBREW_PREFIX}",
                              "--sysconfdir=#{etc}/luarocks52", "--with-lua=#{prefix}",
                              "--lua-version=5.2", "--versioned-rocks-dir", "--force-config=#{etc}/luarocks52"
        system "make", "build"
        system "make", "install"

        (share+"lua/5.2/luarocks").install_symlink Dir["#{libexec}/share/lua/5.2/luarocks/*"]
        bin.install_symlink libexec/"bin/luarocks-5.2"
        bin.install_symlink libexec/"bin/luarocks-admin-5.2"

        # This block ensures luarock exec scripts don't break across updates.
        inreplace libexec/"share/lua/5.2/luarocks/site_config.lua" do |s|
          s.gsub! libexec.to_s, opt_libexec
          s.gsub! include.to_s, "#{HOMEBREW_PREFIX}/include"
          s.gsub! lib.to_s, "#{HOMEBREW_PREFIX}/lib"
          s.gsub! bin.to_s, "#{HOMEBREW_PREFIX}/bin"
        end
      end
    end
  end

  def pc_file; <<-EOS.undent
    V= 5.2
    R= 5.2.3
    prefix=#{HOMEBREW_PREFIX}
    INSTALL_BIN= ${prefix}/bin
    INSTALL_INC= ${prefix}/include
    INSTALL_LIB= ${prefix}/lib
    INSTALL_MAN= ${prefix}/share/man/man1
    INSTALL_LMOD= ${prefix}/share/lua/${V}
    INSTALL_CMOD= ${prefix}/lib/lua/${V}
    exec_prefix=${prefix}
    libdir=${exec_prefix}/lib
    includedir=${prefix}/include

    Name: Lua
    Description: An Extensible Extension Language
    Version: 5.2.3
    Requires:
    Libs: -L${libdir} -llua -lm
    Cflags: -I${includedir}
    EOS
  end

  def caveats; <<-EOS.undent
    Please be aware due to the way Luarocks is designed any binaries installed
    via Luarocks-5.2 AND 5.1 will overwrite each other in #{HOMEBREW_PREFIX}/bin.

    This is, for now, unavoidable. If this is troublesome for you, you can build
    rocks with the `--tree=` command to a special, non-conflicting location and
    then add that to your `$PATH`.

    If you have existing Rocks trees in $HOME, you will need to migrate them to the new
    location manually. You will only have to do this once.
    EOS
  end

  test do
    system "#{bin}/lua", "-e", "print ('Ducks are cool')"

    if File.exist?(bin/"luarocks-5.2")
      mkdir testpath/"luarocks"
      system bin/"luarocks-5.2", "install", "moonscript", "--tree=#{testpath}/luarocks"
      assert File.exist? testpath/"luarocks/bin/moon"
    end
  end
end

__END__
diff --git a/Makefile b/Makefile
index bd9515f..5940ba9 100644
--- a/Makefile
+++ b/Makefile
@@ -41,7 +41,7 @@ PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris
 # What to install.
 TO_BIN= lua luac
 TO_INC= lua.h luaconf.h lualib.h lauxlib.h lua.hpp
-TO_LIB= liblua.a
+TO_LIB= liblua.5.2.3.dylib
 TO_MAN= lua.1 luac.1

 # Lua version and release.
@@ -63,6 +63,8 @@ install: dummy
	cd src && $(INSTALL_DATA) $(TO_INC) $(INSTALL_INC)
	cd src && $(INSTALL_DATA) $(TO_LIB) $(INSTALL_LIB)
	cd doc && $(INSTALL_DATA) $(TO_MAN) $(INSTALL_MAN)
+	ln -s -f liblua.5.2.3.dylib $(INSTALL_LIB)/liblua.5.2.dylib
+	ln -s -f liblua.5.2.dylib $(INSTALL_LIB)/liblua.dylib

 uninstall:
	cd src && cd $(INSTALL_BIN) && $(RM) $(TO_BIN)
diff --git a/src/Makefile b/src/Makefile
index 8c9ee67..7f92407 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -28,7 +28,7 @@ MYOBJS=

 PLATS= aix ansi bsd freebsd generic linux macosx mingw posix solaris

-LUA_A=	liblua.a
+LUA_A=	liblua.5.2.3.dylib
 CORE_O=	lapi.o lcode.o lctype.o ldebug.o ldo.o ldump.o lfunc.o lgc.o llex.o \
	lmem.o lobject.o lopcodes.o lparser.o lstate.o lstring.o ltable.o \
	ltm.o lundump.o lvm.o lzio.o
@@ -56,11 +56,12 @@ o:	$(ALL_O)
 a:	$(ALL_A)

 $(LUA_A): $(BASE_O)
-	$(AR) $@ $(BASE_O)
-	$(RANLIB) $@
+	$(CC) -dynamiclib -install_name HOMEBREW_PREFIX/lib/liblua.5.2.dylib \
+		-compatibility_version 5.2 -current_version 5.2.3 \
+		-o liblua.5.2.3.dylib $^

 $(LUA_T): $(LUA_O) $(LUA_A)
-	$(CC) -o $@ $(LDFLAGS) $(LUA_O) $(LUA_A) $(LIBS)
+	$(CC) -fno-common $(MYLDFLAGS) -o $@ $(LUA_O) $(LUA_A) -L. -llua.5.2.3 $(LIBS)

 $(LUAC_T): $(LUAC_O) $(LUA_A)
	$(CC) -o $@ $(LDFLAGS) $(LUAC_O) $(LUA_A) $(LIBS)
@@ -106,7 +107,7 @@ linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lreadline"

 macosx:
-	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS="-lreadline" CC=cc
+	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX -fno-common" SYSLIBS="-lreadline" CC=cc

 mingw:
	$(MAKE) "LUA_A=lua52.dll" "LUA_T=lua.exe" \
