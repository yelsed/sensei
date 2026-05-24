use rand::seq::SliceRandom;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Deserialize, Serialize, Clone)]
pub struct Tip {
    pub topic: String,
    pub tip: String,
    pub tags: Vec<String>,
}

pub fn load_tips(path: &Path) -> Vec<Tip> {
    if let Ok(content) = fs::read_to_string(path) {
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        bundled_tips()
    }
}

pub fn get_tip(tips: &[Tip], topic: Option<&str>) -> Option<Tip> {
    let mut rng = rand::thread_rng();
    let filtered: Vec<&Tip> = if let Some(t) = topic {
        tips.iter().filter(|tip| tip.topic == t).collect()
    } else {
        tips.iter().collect()
    };
    filtered.choose(&mut rng).map(|t| (*t).clone())
}

pub fn list_topics(tips: &[Tip]) -> Vec<String> {
    let mut topics: Vec<String> = tips.iter().map(|t| t.topic.clone()).collect();
    topics.sort();
    topics.dedup();
    topics
}

fn bundled_tips() -> Vec<Tip> {
    let json = include_str!("../tips/default.json");
    serde_json::from_str(json).unwrap_or_default()
}
