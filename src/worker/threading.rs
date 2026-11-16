use crate::session::{Context, THREADING};
use crate::{digest, hex};
use anyhow::{Context as _, Result, ensure};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Seek, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

const NAME: &str = "GDK_2604.4.7897.zip";
const URL: &str = "https://github.com/microsoft/GDK/releases/download/April-2026-Update-4-v2604.4.7897/GDK_2604.4.7897.zip";
const SIZE: u64 = 1315537904;
const SHA: &str = "3da3f104fa66bb3ee1299b3dc8c0a3ecac1cb56a4cf04136b8595942272017eb";
const OFFSET: u64 = 1101515484;
const COMPRESSED: u64 = 196592307;
const UNPACKED: u64 = 198332601;
const MEMBER: &str = "f8d5f3ebe7339d9d65ebf4b4d68cb7a5281c0f944acafd613ccc68d7d908baed";

pub fn space(path: &Path) -> Result<u64> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(path.as_os_str().as_bytes())?;
    let mut info = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    // statvfs initialises the supplied structure only when it succeeds
    ensure!(
        unsafe { libc::statvfs(path.as_ptr(), info.as_mut_ptr()) } == 0,
        "Couldn’t check available disk space"
    );
    let info = unsafe { info.assume_init() };
    Ok(u64::try_from(
        u128::from(info.f_bavail) * u128::from(info.f_frsize),
    )?)
}

fn copy(
    source: &mut impl Read,
    output: &mut impl Write,
    limit: u64,
    cancelled: &AtomicBool,
) -> Result<u64> {
    let mut buffer = [0; 65536];
    let mut count = 0_u64;
    loop {
        ensure!(
            !cancelled.load(Ordering::Relaxed),
            "The Microsoft component download was cancelled"
        );
        let n = source.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        count = count
            .checked_add(n as u64)
            .context("The Microsoft component is larger than expected")?;
        ensure!(
            count <= limit,
            "The Microsoft component is larger than expected"
        );
        output.write_all(&buffer[..n])?;
    }
    Ok(count)
}

fn extract<R: Read + Seek>(bundle: R, temporary: &Path, cancelled: &AtomicBool) -> Result<Vec<u8>> {
    let mut bundle = zip::ZipArchive::new(bundle)?;
    let mut package = bundle.by_name("GamingServicesTcui-Package_35.116.29001.0_x64.appx")?;
    ensure!(
        package.size() <= UNPACKED,
        "The pinned Gaming Services package has an unexpected size"
    );
    let mut appx = tempfile::NamedTempFile::new_in(temporary)?;
    copy(&mut package, appx.as_file_mut(), UNPACKED, cancelled)?;
    appx.rewind()?;
    let mut appx = zip::ZipArchive::new(appx.as_file_mut())?;
    let names: Vec<_> = appx
        .file_names()
        .collect::<std::result::Result<Vec<_>, _>>()?
        .into_iter()
        .filter(|name| name.eq_ignore_ascii_case("xgameruntime.dll"))
        .map(|name| name.into_owned())
        .collect();
    ensure!(
        names.len() == 1,
        "The pinned Gaming Services package has an unexpected layout"
    );
    let mut file = appx.by_name(&names[0])?;
    ensure!(
        file.size() <= 4 * 1024 * 1024,
        "The Microsoft threading component is larger than expected"
    );
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)?;
    ensure!(
        hex(&Sha256::digest(&bytes)) == THREADING,
        "Microsoft’s extracted threading DLL failed checksum validation"
    );
    Ok(bytes)
}

pub fn acquire(context: &Context, cancelled: &AtomicBool) -> Result<()> {
    let destination = context.root.join("runtime/xgameruntime.dll.threading");
    if destination.exists() || destination.is_symlink() {
        ensure!(
            !destination.is_symlink() && digest(&destination)? == THREADING,
            "The existing threading DLL differs from the pinned Microsoft file; it was preserved"
        );
        return Ok(());
    }
    let downloads = context.root.join("downloads");
    ensure!(
        !downloads.is_symlink(),
        "A link blocks the component download directory"
    );
    fs::create_dir_all(&downloads)?;
    ensure!(
        space(&downloads)? >= COMPRESSED + 256 * 1024 * 1024,
        "Not enough free space for the Microsoft component"
    );
    let archive = downloads.join(NAME);
    ensure!(
        !archive.is_symlink(),
        "The GDK archive path is a symbolic link; it was preserved"
    );
    let partial = archive.with_extension("zip.part");
    ensure!(
        !partial.is_symlink(),
        "The GDK partial download is a symbolic link; it was preserved"
    );
    if partial.exists() {
        let size = fs::metadata(&partial)?.len();
        ensure!(
            size <= SIZE,
            "The GDK partial download is larger than the pinned release; it was preserved"
        );
        if size == SIZE && !archive.exists() {
            ensure!(
                digest(&partial)? == SHA,
                "The downloaded GDK failed checksum validation; the partial file was preserved"
            );
            fs::hard_link(&partial, &archive)?;
            fs::remove_file(&partial)?;
        }
    }
    let temporary = tempfile::Builder::new()
        .prefix(".gaming-")
        .tempdir_in(&downloads)?;
    let bytes = if archive.exists() {
        ensure!(
            fs::metadata(&archive)?.len() == SIZE && digest(&archive)? == SHA,
            "The GDK archive differs from Microsoft’s published release digest; it was preserved"
        );
        let mut archive = zip::ZipArchive::new(File::open(&archive)?)?;
        let mut bundle = archive.by_name("Installers/GamingServices.appxbundle")?;
        ensure!(
            bundle.size() == UNPACKED,
            "The Microsoft component has an unexpected size"
        );
        let mut file = tempfile::NamedTempFile::new_in(temporary.path())?;
        copy(&mut bundle, file.as_file_mut(), UNPACKED, cancelled)?;
        file.rewind()?;
        extract(file, temporary.path(), cancelled)?
    } else {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(300))
            .connect_timeout(Duration::from_secs(30))
            .build()?;
        let mut response = client
            .get(URL)
            .header(
                reqwest::header::RANGE,
                format!("bytes={OFFSET}-{}", OFFSET + COMPRESSED - 1),
            )
            .send()?
            .error_for_status()?;
        ensure!(
            response.url().scheme() == "https"
                && response.status() == reqwest::StatusCode::PARTIAL_CONTENT,
            "Microsoft component download failed range verification; please retry"
        );
        let mut compressed = tempfile::NamedTempFile::new_in(temporary.path())?;
        let size = copy(
            &mut response,
            compressed.as_file_mut(),
            COMPRESSED,
            cancelled,
        )?;
        ensure!(
            size == COMPRESSED && digest(compressed.path())? == MEMBER,
            "Microsoft component download failed verification; please retry"
        );
        compressed.rewind()?;
        let mut decoder = flate2::read::DeflateDecoder::new(compressed);
        let mut bundle = tempfile::NamedTempFile::new_in(temporary.path())?;
        ensure!(
            copy(&mut decoder, bundle.as_file_mut(), UNPACKED, cancelled)? == UNPACKED,
            "The Microsoft component has an unexpected size"
        );
        bundle.rewind()?;
        extract(bundle, temporary.path(), cancelled)?
    };
    fs::create_dir_all(destination.parent().context("Missing runtime directory")?)?;
    let mut stage = tempfile::NamedTempFile::new_in(
        destination.parent().context("Missing runtime directory")?,
    )?;
    stage.write_all(&bytes)?;
    stage.as_file().sync_all()?;
    stage
        .persist_noclobber(destination)
        .map_err(|error| error.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_oversized_and_cancelled_transfers() {
        let cancelled = AtomicBool::new(false);
        assert!(copy(&mut &b"12345"[..], &mut Vec::new(), 4, &cancelled).is_err());
        cancelled.store(true, Ordering::Relaxed);
        assert!(copy(&mut &b"12"[..], &mut Vec::new(), 4, &cancelled).is_err());
    }
}
