use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Parser)]
#[command(name = "docker-find")]
#[command(about = "Smart Docker container finder with caching and fuzzy search")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Find containers by name/pattern (use "-" for fzf selection)
    Find {
        /// Container name pattern (use "-" for interactive selection)
        pattern: Option<String>,
    },
    /// Find containers with smart defaults (cache → smart → fzf)
    F {
        /// Container name pattern, "--" for default behavior, "-" for explicit fzf
        pattern: Option<String>,
    },
    /// Get smart default container for current directory
    Smart,
    /// Clear cache for current directory
    ClearCache,
}

#[derive(Serialize, Deserialize, Debug)]
struct CacheEntry {
    container_name: String,
    timestamp: u64,
}

struct DockerFind {
    cache_file: PathBuf,
}

impl DockerFind {
    fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let cache_dir = dirs::cache_dir()
            .ok_or("Could not determine cache directory")?
            .join("docker-find");

        fs::create_dir_all(&cache_dir)?;

        let pwd = env::current_dir()?;
        let mut hasher = Sha256::new();
        hasher.update(pwd.to_string_lossy().as_bytes());
        let hash = format!("{:x}", hasher.finalize());

        let cache_file = cache_dir.join(format!("{}.json", &hash[..16]));

        Ok(DockerFind { cache_file })
    }

    fn get_running_containers(&self) -> Result<Vec<(String, String)>, Box<dyn std::error::Error>> {
        let output = Command::new("docker")
            .args(&["ps", "--format", "{{.Names}}\t{{.ID}}"])
            .output()?;

        if !output.status.success() {
            return Err("Failed to list Docker containers".into());
        }

        let containers: Vec<(String, String)> = String::from_utf8(output.stdout)?
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.split('\t').collect();
                if parts.len() < 2 {
                    return None;
                }
                Some((parts[0].to_string(), parts[1].to_string()))
            })
            .collect();

        Ok(containers)
    }

    fn find_container(&self, pattern: &str) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let containers = self.get_running_containers()?;

        let matches: Vec<String> = containers
            .into_iter()
            .filter(|(name, _)| name.contains(pattern))
            .map(|(_, id)| id)
            .collect();

        Ok(matches)
    }

    fn fzf_select(&self) -> Result<String, Box<dyn std::error::Error>> {
        let containers = self.get_running_containers()?;

        if containers.is_empty() {
            return Err("No running containers found".into());
        }

        // Format containers for fzf display
        let container_list: String = containers
            .iter()
            .map(|(name, id)| format!("{}\t{}", name, id))
            .collect::<Vec<_>>()
            .join("\n");

        // Use fzf for selection
        let mut fzf = Command::new("fzf")
            .arg("--delimiter=\t")
            .arg("--with-nth=1")
            .arg("--preview=echo 'Container: {}' | cut -d$'\\t' -f1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;

        if let Some(stdin) = fzf.stdin.as_mut() {
            stdin.write_all(container_list.as_bytes())?;
        }

        let output = fzf.wait_with_output()?;

        if !output.status.success() {
            return Err("No container selected".into());
        }

        let selected = String::from_utf8(output.stdout)?;
        let parts: Vec<&str> = selected.trim().split('\t').collect();
        if parts.len() < 2 {
            return Err("Invalid selection format".into());
        }
        
        let container_id = parts[1].to_string();
        Ok(container_id)
    }

    fn get_smart_default(&self) -> Result<Option<String>, Box<dyn std::error::Error>> {
        // 1. Try cache first
        if let Ok(cached) = self.load_cache() {
            if let Some(container_id) = self.find_container(&cached.container_name)?.first() {
                return Ok(Some(container_id.clone()));
            }

            // Try prefix match for running containers
            let containers = self.get_running_containers()?;
            for (name, id) in containers {
                if name.starts_with(&cached.container_name) {
                    return Ok(Some(id));
                }
            }
        }

        // 2. Try docker-compose services
        if let Ok(service_name) = self.find_compose_service() {
            if let Some(container_id) = self.find_container(&service_name)?.first() {
                return Ok(Some(container_id.clone()));
            }
        }

        // 3. Try containers with directory name
        let current_dir = env::current_dir()?;
        let dir_name = current_dir
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");

        let containers = self.get_running_containers()?;
        for (name, id) in &containers {
            if name.contains(dir_name) {
                return Ok(Some(id.clone()));
            }
        }

        // 4. If only one container running, use it
        if containers.len() == 1 {
            return Ok(Some(containers[0].1.clone()));
        }

        Ok(None)
    }

    fn find_compose_service(&self) -> Result<String, Box<dyn std::error::Error>> {
        let compose_files = ["docker-compose.yml", "docker-compose.yaml"];

        for compose_file in &compose_files {
            if !PathBuf::from(compose_file).exists() {
                continue;
            }

            let content = fs::read_to_string(compose_file)?;

            // Look for common service names first
            let common_services = ["app", "web", "api", "main", "server"];
            for service in &common_services {
                if !content.contains(&format!("{}:", service)) {
                    continue;
                }

                let current_dir = env::current_dir()?;
                let dir_name = current_dir
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("");

                let container_name = format!("{}_{}", dir_name, service);
                if !self.find_container(&container_name)?.is_empty() {
                    return Ok(container_name);
                }
            }

            // Fall back to first service
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') || !trimmed.contains(':') || trimmed.starts_with(' ') {
                    continue;
                }

                if let Some(service) = trimmed.split(':').next() {
                    let current_dir = env::current_dir()?;
                    let dir_name = current_dir
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("");

                    let container_name = format!("{}_{}", dir_name, service);
                    if !self.find_container(&container_name)?.is_empty() {
                        return Ok(container_name);
                    }
                }
            }
        }

        Err("No compose services found".into())
    }

    fn save_cache(&self, container_name: &str) -> Result<(), Box<dyn std::error::Error>> {
        let cache_name = match container_name.contains("-run-") {
            true => container_name
                .split("-run-")
                .next()
                .unwrap_or(container_name),
            false => container_name,
        };

        let cache_entry = CacheEntry {
            container_name: cache_name.to_string(),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs(),
        };

        let json = serde_json::to_string(&cache_entry)?;
        fs::write(&self.cache_file, json)?;
        Ok(())
    }

    fn load_cache(&self) -> Result<CacheEntry, Box<dyn std::error::Error>> {
        let content = fs::read_to_string(&self.cache_file)?;
        let cache_entry: CacheEntry = serde_json::from_str(&content)?;
        Ok(cache_entry)
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    let docker_find = DockerFind::new()?;

    match cli.command {
        Some(Commands::Find { pattern }) => {
            let Some(pattern) = pattern else {
                // List all containers
                let containers = docker_find.get_running_containers()?;
                for (name, id) in containers {
                    println!("{}\t{}", name, id);
                }
                return Ok(());
            };

            if pattern == "-" {
                // Use fzf for interactive selection
                let container_id = docker_find.fzf_select()?;
                println!("{}", container_id);
                // Get container name for caching
                let containers = docker_find.get_running_containers()?;
                if let Some((name, _)) = containers.iter().find(|(_, id)| id == &container_id) {
                    docker_find.save_cache(name)?;
                }
                return Ok(());
            }

            // Find containers matching pattern
            let container_ids = docker_find.find_container(&pattern)?;
            if container_ids.is_empty() {
                eprintln!("No containers found matching '{}'", pattern);
                std::process::exit(1);
            }
            for id in container_ids {
                println!("{}", id);
            }
        }
        Some(Commands::F { pattern }) => {
            let Some(pattern) = pattern else {
                // Default behavior: cache → smart → fzf
                let Some(smart_default) = docker_find.get_smart_default()? else {
                    let container_id = docker_find.fzf_select()?;
                    println!("{}", container_id);
                    // Get container name for caching
                    let containers = docker_find.get_running_containers()?;
                    if let Some((name, _)) = containers.iter().find(|(_, id)| id == &container_id) {
                        docker_find.save_cache(name)?;
                    }
                    return Ok(());
                };
                println!("{}", smart_default);
                return Ok(());
            };

            if pattern == "--" {
                // Same as no pattern - default behavior
                let Some(smart_default) = docker_find.get_smart_default()? else {
                    let container_id = docker_find.fzf_select()?;
                    println!("{}", container_id);
                    // Get container name for caching
                    let containers = docker_find.get_running_containers()?;
                    if let Some((name, _)) = containers.iter().find(|(_, id)| id == &container_id) {
                        docker_find.save_cache(name)?;
                    }
                    return Ok(());
                };
                println!("{}", smart_default);
                return Ok(());
            }

            if pattern == "-" {
                // Explicit fzf selection (skip smart default)
                let container_id = docker_find.fzf_select()?;
                println!("{}", container_id);
                // Get container name for caching
                let containers = docker_find.get_running_containers()?;
                if let Some((name, _)) = containers.iter().find(|(_, id)| id == &container_id) {
                    docker_find.save_cache(name)?;
                }
                return Ok(());
            }

            // Find containers matching pattern
            let container_ids = docker_find.find_container(&pattern)?;
            if container_ids.is_empty() {
                eprintln!("No containers found matching '{}'", pattern);
                std::process::exit(1);
            }
            for id in container_ids {
                println!("{}", id);
            }
        }
        Some(Commands::Smart) => {
            let Some(container) = docker_find.get_smart_default()? else {
                eprintln!("No smart default found");
                std::process::exit(1);
            };
            println!("{}", container);
        }
        Some(Commands::ClearCache) => {
            if !docker_find.cache_file.exists() {
                println!("No cache found for current directory");
                return Ok(());
            }
            fs::remove_file(&docker_find.cache_file)?;
            println!("Cache cleared for current directory");
        }
        None => {
            // No subcommand provided, show help
            Cli::parse_from(&["docker-find", "--help"]);
        }
    }

    Ok(())
}
