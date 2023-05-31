use clap::Parser;
use execute::Execute;
use futures::{
    channel::mpsc::{channel, Receiver},
    SinkExt, StreamExt,
};
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use regex::Regex;
use std::process::{Command, Stdio};

#[derive(Parser)]
struct Args {
    registry_path: std::path::PathBuf,
    pipeline_script_path: std::path::PathBuf,
    cleanup_script_path: std::path::PathBuf,
}

/// Async, futures channel based event watching
fn main() {
    let args = Args::parse();
    println!("watching {:?}", args.registry_path);

    futures::executor::block_on(async {
        if let Err(e) = async_watch(args).await {
            println!("error: {:?}", e)
        }
    });
}

fn async_watcher() -> notify::Result<(RecommendedWatcher, Receiver<notify::Result<Event>>)> {
    let (mut tx, rx) = channel(1);

    // Automatically select the best implementation for your platform.
    // You can also access each implementation directly e.g. INotifyWatcher.
    let watcher = RecommendedWatcher::new(
        move |res| {
            futures::executor::block_on(async {
                tx.send(res).await.unwrap();
            })
        },
        Config::default(),
    )?;

    Ok((watcher, rx))
}

async fn async_watch(args: Args) -> notify::Result<()> {
    let (mut watcher, mut rx) = async_watcher()?;

    let path = args.registry_path.as_path();

    // Add a path to be watched. All files and directories at that path and
    // below will be monitored for changes.
    watcher.watch(path.as_ref(), RecursiveMode::Recursive)?;

    while let Some(res) = rx.next().await {
        match res {
            Ok(event) => {
                if event.kind == EventKind::Create(notify::event::CreateKind::Folder) {
                    if event.paths[0]
                        .as_path()
                        .starts_with("/var/lib/registry/docker/registry/v2/repositories")
                        && event.paths[0].as_path().ends_with("current")
                    {
                        let regex_pattern = r"/repositories/(?P<repository>[^/]+)/_manifests/tags/(?P<tag>[^/]+)/current";
                        let regex = Regex::new(&regex_pattern).unwrap();

                        if let Some(captures) =
                            regex.captures(event.paths[0].as_path().to_str().unwrap())
                        {
                            let repository = captures.name("repository").unwrap().as_str();
                            let tag = captures.name("tag").unwrap().as_str();

                            println!("Repository: {}", repository);
                            println!("Tag: {}", tag);

                            let mut command = Command::new(format!(
                                "{}",
                                args.pipeline_script_path.to_str().unwrap(),
                            ));

                            command.arg(repository);
                            command.arg(tag);

                            let mut cmd = command
                                .stdout(Stdio::inherit())
                                .stderr(Stdio::inherit())
                                .spawn()
                                .unwrap();

                            let status = cmd.wait();

                            if !status.unwrap().success() {
                                eprintln!("Actions script failed for {}:{}", repository, tag);
                            }

                            let mut cleanup_cmd = Command::new(format!(
                                "{}",
                                args.cleanup_script_path.to_str().unwrap(),
                            ));

                            cleanup_cmd.arg(repository);
                            cleanup_cmd.arg(tag);

                            cleanup_cmd
                                .stdout(Stdio::inherit())
                                .stderr(Stdio::inherit())
                                .spawn()
                                .unwrap();
                        }
                    }
                }
            }

            Err(e) => println!("watch error: {:?}", e),
        }
    }

    Ok(())
}
