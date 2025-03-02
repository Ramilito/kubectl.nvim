
use std::collections::HashMap;
use crate::processors::processor::Processor;

pub mod processor;
pub mod default;
pub mod pod;

pub fn get_processors() -> HashMap<&'static str, Box<dyn Processor>> {
    let mut map: HashMap<&str, Box<dyn Processor>> = HashMap::new();
    map.insert("default", Box::new(default::DefaultProcessor));
    map.insert("pod", Box::new(pod::PodProcessor));
    map
}
