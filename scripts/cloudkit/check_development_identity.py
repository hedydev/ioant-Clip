"""Check a team's existing Apple Development identity and sign a disposable binary.

Read public certificates only. No export of private keys, no keychain edits,
no provisioning updates, no network registration, no modification of apps.
Do not log certificate subjects, fingerprints, raw keychain output or secrets.
"""
import argparse
import hashlib
import pathlib
import re
import ssl
import subprocess
import tempfile

def run(args, timeout=20, input=None):
    return subprocess.run(args, input=input, capture_output=True, timeout=timeout)

def identity_hashes(output):
    return set(re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"Apple Development:[^"\n]+"', output, re.M))

def matches_team(subject, team):
    return re.search(r'(?:^|,)OU=' + re.escape(team) + r'(?:,|$)', subject.removeprefix("subject=").strip()) is not None

def discover(team):
    identities = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])
    if identities.returncode:
        raise RuntimeError("identity inventory unavailable")
    hashes = {h.upper() for h in identity_hashes(identities.stdout.decode(errors="replace"))}
    certs = run(["/usr/bin/security", "find-certificate", "-a", "-c", "Apple Development", "-p"])
    if certs.returncode and hashes:
        raise RuntimeError("public certificate inventory unavailable")
    candidates = set()
    resolved = set()
    for pem in re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', certs.stdout, re.S):
        digest = hashlib.sha1(ssl.PEM_cert_to_DER_cert(pem.decode("ascii"))).hexdigest().upper()
        if digest not in hashes:
            continue
        subject = run(["/usr/bin/openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"], input=pem)
        if subject.returncode:
            raise RuntimeError("certificate team inspection failed")
        resolved.add(digest)
        if matches_team(subject.stdout.decode(errors="replace"), team):
            candidates.add(digest)
    return hashes, candidates, resolved

def verify_signing(candidates, team):
    with tempfile.TemporaryDirectory(prefix="clip-signing-probe-") as temp:
        root = pathlib.Path(temp)
        src, app = root/"probe.c", root/"probe"
        src.write_text("int main(void) { return 0; }\n")
        compiler = run(["/usr/bin/xcrun", "clang", str(src), "-o", str(app)], timeout=45)
        if compiler.returncode:
            print("BLOCKED: could not compile disposable signing probe")
            return False
        for index, fingerprint in enumerate(sorted(candidates), 1):
            try:
                signed = run(["/usr/bin/codesign", "--force", "--sign", fingerprint, "--timestamp=none", str(app)], timeout=35)
            except subprocess.TimeoutExpired:
                print("BLOCKED: signing probe timed out; possible keychain authorization required; no certificate requested")
                return False
            if signed.returncode:
                print("Existing identity", index, "signing unavailable; no keychain changes made")
                continue
            verify = run(["/usr/bin/codesign", "--verify", "--strict", str(app)])
            detail = run(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
            lines = detail.stderr.decode(errors="replace").splitlines()
            if verify.returncode == 0 and detail.returncode == 0 and "TeamIdentifier=" + team in lines and any(line.startswith("Authority=Apple Development:") for line in lines):
                print("PASS: Apple Development private-key signing and strict signature verification succeeded for expected team")
                return True
        print("BLOCKED: no matching identity passed the signing probe; existing certificates retained")
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        raise SystemExit("Invalid expected Apple team")
    try:
        hashes, candidates, resolved = discover(args.team)
        print("Valid Apple Development identities:", len(hashes))
        print("Resolved public certificates:", len(resolved))
        print("Valid identities in expected team:", len(candidates))
        if candidates:
            verify_signing(candidates, args.team)
        elif hashes != resolved:
            print("UNKNOWN: some valid identity certificates could not be matched; do not request a new certificate")
        else:
            print("NO_MATCH: no locally valid Apple Development identity for expected team; verify existing portal certificates before requesting one")
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired):
        print("UNKNOWN: local signing inventory incomplete; no certificate requested")
        raise SystemExit(1)

if __name__ == "__main__":
    main()
