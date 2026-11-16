use anyhow::{Context, Result, ensure};
use std::path::PathBuf;

pub fn command(args: &mut Vec<String>, usage: &str) -> Result<String> {
    ensure!(!args.is_empty(), "Usage: {usage}");
    Ok(args.remove(0))
}

pub fn option(args: &mut Vec<String>, name: &str) -> Result<Option<String>> {
    let Some(index) = args.iter().position(|arg| arg == name) else {
        return Ok(None);
    };
    args.remove(index);
    let value = args
        .get(index)
        .filter(|value| !value.starts_with("--"))
        .with_context(|| format!("{name} needs a value"))?
        .clone();
    args.remove(index);
    ensure!(
        !args.iter().any(|arg| arg == name),
        "Repeated option: {name}"
    );
    Ok(Some(value))
}

pub fn flag(args: &mut Vec<String>, name: &str) -> bool {
    if let Some(index) = args.iter().position(|arg| arg == name) {
        args.remove(index);
        true
    } else {
        false
    }
}

pub fn path(value: String) -> Result<PathBuf> {
    ensure!(!value.is_empty(), "Choose a non-empty path");
    let value = if let Some(tail) = value.strip_prefix("~/") {
        PathBuf::from(std::env::var_os("HOME").context("Missing home directory")?).join(tail)
    } else {
        PathBuf::from(value)
    };
    Ok(std::path::absolute(value)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn options_and_paths() -> Result<()> {
        let mut args = vec!["--market".into(), "AU".into(), "--jobs".into(), "2".into()];
        assert_eq!(option(&mut args, "--market")?, Some("AU".into()));
        assert_eq!(option(&mut args, "--jobs")?, Some("2".into()));
        assert!(args.is_empty());
        assert!(option(&mut vec!["--market".into()], "--market").is_err());
        assert!(
            option(
                &mut vec![
                    "--market".into(),
                    "AU".into(),
                    "--market".into(),
                    "US".into()
                ],
                "--market"
            )
            .is_err()
        );
        assert!(path("relative".into())?.is_absolute());
        assert!(path("~/worlds".into())?.is_absolute());
        assert!(path(String::new()).is_err());
        Ok(())
    }
}
