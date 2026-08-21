module main

import json

pub struct Pattern {
pub mut:
	from string
	to   string
}

pub struct Scheme {
pub mut:
	colors       []Color @[skip]
	image        string
	theme        string
	pigments     []string
	scheme       string
	walldir      string
	config       string @[skip]
	cache        string @[skip]
	scripts      []string
	patterns     []Pattern
	looop        int
	palette      string
	sort         string
	saturation   f64
	illumination f64
	hue          f64
	difference   f64
	blend        f64
	norandom     bool
}

pub fn (s Scheme) is_dark() bool {
	return s.theme != 'light'
}

// Overlay every value the incoming scheme actually sets
pub fn (mut s Scheme) modi(new Scheme) {
	if new.colors.len > 0 {
		s.colors = new.colors.clone()
	}
	if new.pigments.len > 0 {
		s.pigments = new.pigments.clone()
	}
	if new.image != '' {
		s.image = new.image
	}
	if new.scheme != '' {
		s.scheme = new.scheme
	}
	if new.walldir != '' {
		s.walldir = new.walldir
	}
	if new.config != '' {
		s.config = new.config
	}
	if new.cache != '' {
		s.cache = new.cache
	}
	if new.scripts.len > 0 {
		s.scripts = new.scripts.clone()
	}
	if new.patterns.len > 0 {
		s.patterns = new.patterns.clone()
	}
	if new.theme != '' {
		s.theme = new.theme
	}
	if new.palette != '' {
		s.palette = new.palette
	}
	if new.sort != '' {
		s.sort = new.sort
	}
	if new.saturation != 0.0 {
		s.saturation = new.saturation
	}
	if new.illumination != 0.0 {
		s.illumination = new.illumination
	}
	if new.hue != 0.0 {
		s.hue = new.hue
	}
	if new.difference != 0.0 {
		s.difference = new.difference
	}
	if new.blend != 0.0 {
		s.blend = new.blend
	}
	if new.norandom {
		s.norandom = new.norandom
	}
}

pub fn (s Scheme) to_json() string {
	return json.encode(s)
}

pub fn scheme_from_json(data string) !Scheme {
	return json.decode(Scheme, data)!
}

pub struct Special {
pub mut:
	background string
	foreground string
	cursor     string
}

pub struct ProfileVec {
pub mut:
	wallpaper string
	theme     string
	special   Special
	colors    []string
}

pub struct ProfileMap {
pub mut:
	wallpaper string
	theme     string
	special   Special
	colors    map[string]string
}
