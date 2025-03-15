use crate::processors::processor::Processor;
use std::collections::HashMap;

pub mod default;
pub mod deployment;
pub mod pod;
pub mod processor;

pub fn get_processors() -> HashMap<&'static str, Box<dyn Processor>> {
    let mut map: HashMap<&str, Box<dyn Processor>> = HashMap::new();
    map.insert("default", Box::new(default::DefaultProcessor));
    map.insert("pod", Box::new(pod::PodProcessor));
    map.insert("deployment", Box::new(deployment::DeploymentProcessor));
    map
}
