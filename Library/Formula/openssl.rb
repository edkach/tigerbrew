class Openssl < Formula
  homepage "https://openssl.org"
  url "https://www.openssl.org/source/openssl-1.0.2a.tar.gz"
  mirror "https://raw.githubusercontent.com/DomT4/LibreMirror/master/OpenSSL/openssl-1.0.2a.tar.gz"
  sha256 "15b6393c20030aab02c8e2fe0243cb1d1d18062f6c095d67bca91871dc7f324a"
  # Work around this being parsed as an alpha version by our
  # version detection code.
  version "1.0.2a-1"

  bottle do
    sha1 "fd35708951173dd4d5e40164b0328e4b3c93efe7" => :tiger_altivec
    sha1 "d90b9052b42efcf5d44f190de80a6d94b8ef4112" => :leopard_g3
    sha1 "084cb268b148bf900351e2761cee4374f3a903a8" => :leopard_altivec
  end

  option :universal
  option "without-check", "Skip build-time tests (not recommended)"

  depends_on "makedepend" => :build

  keg_only :provided_by_osx,
    "Apple has deprecated use of OpenSSL in favor of its own TLS and crypto libraries"

  # Remove both patches with the 1.0.2b release.
  # They fix:
  # https://github.com/Homebrew/homebrew/pull/38495
  # https://github.com/Homebrew/homebrew/issues/38491
  # Upstream discussions:
  # https://www.mail-archive.com/openssl-dev@openssl.org/msg38674.html
  patch do
    url "https://github.com/openssl/openssl/commit/6281abc796234.diff"
    sha256 "f8b94201ac2cd7dcdee3b07fb3cd77a2de6b81ea67da9ae075cf06fb0ba73cea"
  end

  patch do
    url "https://github.com/openssl/openssl/commit/dfd3322d72a2.diff"
    sha256 "0602eef6e38368c7b34994deb9b49be1a54037de5e8b814748d55882bfba4eac"
  end

  def arch_args
    {
      :x86_64 => %w[darwin64-x86_64-cc enable-ec_nistp_64_gcc_128],
      :i386   => %w[darwin-i386-cc],
      :ppc    => %w[darwin-ppc-cc],
      :ppc64  => %w[darwin64-ppc-cc enable-ec_nistp-64_gcc_128]
    }
  end

  def configure_args
    args = %W[
      --prefix=#{prefix}
      --openssldir=#{openssldir}
      no-ssl2
      zlib-dynamic
      shared
      enable-cms
    ]

    args << "no-asm" if MacOS.version == :tiger

    args
  end

  def install
    if build.universal?
      ENV.permit_arch_flags
      archs = Hardware::CPU.universal_archs
    elsif MacOS.prefer_64_bit?
      archs = [Hardware::CPU.arch_64_bit]
    else
      archs = [Hardware::CPU.arch_32_bit]
    end

    dirs = []

    archs.each do |arch|
      if build.universal?
        dir = "build-#{arch}"
        dirs << dir
        mkdir dir
        mkdir "#{dir}/engines"
        system "make", "clean"
      end

      ENV.deparallelize
      system "perl", "./Configure", *(configure_args + arch_args[arch])
      system "make", "depend"
      system "make"

      if (MacOS.prefer_64_bit? || arch == MacOS.preferred_arch) && build.with?("check")
        system "make", "test"
      end

      if build.universal?
        cp Dir["*.?.?.?.dylib", "*.a", "apps/openssl"], dir
        cp Dir["engines/**/*.dylib"], "#{dir}/engines"
      end
    end

    system "make", "install", "MANDIR=#{man}", "MANSUFFIX=ssl"

    if build.universal?
      %w[libcrypto libssl].each do |libname|
        system "lipo", "-create", "#{dirs.first}/#{libname}.1.0.0.dylib",
                                  "#{dirs.last}/#{libname}.1.0.0.dylib",
                       "-output", "#{lib}/#{libname}.1.0.0.dylib"
        system "lipo", "-create", "#{dirs.first}/#{libname}.a",
                                  "#{dirs.last}/#{libname}.a",
                       "-output", "#{lib}/#{libname}.a"
      end

      Dir.glob("#{dirs.first}/engines/*.dylib") do |engine|
        libname = File.basename(engine)
        system "lipo", "-create", "#{dirs.first}/engines/#{libname}",
                                  "#{dirs.last}/engines/#{libname}",
                       "-output", "#{lib}/engines/#{libname}"
      end

      system "lipo", "-create", "#{dirs.first}/openssl",
                                "#{dirs.last}/openssl",
                     "-output", "#{bin}/openssl"
    end
  end

  def openssldir
    etc/"openssl"
  end

  def post_install
    keychains = %w[
      /Library/Keychains/System.keychain
      /System/Library/Keychains/SystemRootCertificates.keychain
    ]

    openssldir.mkpath
    (openssldir/"cert.pem").atomic_write `security find-certificate -a -p #{keychains.join(" ")}`

    # Remove this once 1.0.2b lands.
    rm_f openssldir/"certs/Equifax_CA" if MacOS.version == :yosemite
  end if MacOS.version > :leopard

  def caveats; <<-EOS.undent
    To install updated CA certs from Mozilla.org:

        brew install curl-ca-bundle
    EOS
  end

  test do
    # Make sure the necessary .cnf file exists, otherwise OpenSSL gets moody.
    cnf_path = HOMEBREW_PREFIX/"etc/openssl/openssl.cnf"
    assert cnf_path.exist?,
            "OpenSSL requires the .cnf file for some functionality"

    # Check OpenSSL itself functions as expected.
    (testpath/"testfile.txt").write("This is a test file")
    expected_checksum = "91b7b0b1e27bfbf7bc646946f35fa972c47c2d32"
    system "#{bin}/openssl", "dgst", "-sha1", "-out", "checksum.txt", "testfile.txt"
    open("checksum.txt") do |f|
      checksum = f.read(100).split("=").last.strip
      assert_equal checksum, expected_checksum
    end
  end
end
