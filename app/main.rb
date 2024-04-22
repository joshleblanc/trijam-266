require 'app/drakkon/bundle.rb'
require "joshleblanc/drecs/drecs.rb"

include Drecs::Main

GRID = 80
SIZE = 64

world :default, 
  systems: [
    :tick_timer, :gravity, :controls, :acceleration, :manage_platforms, :render_equations, :render_sprites, :render_score, :render_timer,
  ], 
  entities: [
    { timer: { as: :timer }},
    { player: { as: :player }},
    *(1280 / SIZE).to_i.times.map { ({ floor: { position: { x: _1 * SIZE, y: 0 }} }) }
  ]

component :position, x: 1280 / 2, y: SIZE
component :gravity 
component :size, w: SIZE, h: SIZE
component :platform
component :floor
component :sprite, { path: "sprites/spritesheet_default.png", tile_w: GRID, tile_h: GRID, tile_x: 0, tile_y: 0 }
component :accel, { x: 0, y: 0 }
component :on_ground
component :equation, { answer: 0, equation: "" }
component :parent, { parent: nil }

component :max_height, { y: 0 }
component :parts, { parts: [] }
component :time, { left: 10 }

entity :player, :position, :on_ground, :gravity, :size, :max_height, :accel, sprite: { tile_x: 175, tile_y: 0 }
entity :floor, :position, :floor, :size, sprite: { tile_x: 160, tile_y: 80 * 4 }

entity :platform_part, :position, :platform, :size, :parent, sprite: { tile_x: 160, tile_y: 80 * 4 }
entity :platform, :parts, :equation, :position, :size

entity :timer, :time

def generate_equation(odd = true)
  answer = nil
  num_a = nil
  num_b = nil
  operation = nil

  loop do 
    num_a = rand.remap(0, 1, 0, 10).to_i
    num_b = rand.remap(0, 1, 0, 10).to_i
    operation = ["+", "-"].sample

    answer = if operation == "+"
      num_a + num_b
    elsif operation == "-" 
      num_a - num_b
    end

    break if answer.odd? && odd
    break if answer.even? && !odd
  end
  
  { 
    answer: answer,
    equation: "#{num_a} #{operation} #{num_b}"
  }
end

def make_platform(side = :left, y = 0, odd_or_even = :odd)
  
  x = if side == :left 
    rand.remap(0, 1, SIZE, 1280 / 2)
  else 
    rand.remap(0, 1, 1280 / 2, 1280 - SIZE)
  end

  equation = generate_equation(odd_or_even == :odd)

  platform = create_entity(:platform, {
    parts: {
      parts: []
    },
  })

  platform.equation.answer = equation.answer
  platform.equation.equation = equation.equation

  parts = []
  parts << create_entity(:platform_part, {
    position: { 
      x: x - SIZE,
      y: y
    },
    sprite: { 
      tile_x: 80, tile_y: (GRID * 4) - 13
    },
    parent: { 
      parent: platform
    }
  })

  parts << create_entity(:platform_part, {
    position: { 
      x: x,
      y: y
    },
    sprite: { 
      tile_x: 160, tile_y: (GRID * 4)
    },
    parent: { 
      parent: platform
    }
  })

  parts << create_entity(:platform_part, {
    position: { 
      x: x + 64,
      y: y
    },
    sprite: { 
      tile_x: 0, tile_y: (GRID * 6) - 13
    },
    parent: { 
      parent: platform
    }
  })

  platform.position.x = parts.map { _1.position.x }.min + SIZE + (SIZE / 2)
  platform.position.y = parts.map { _1.position.y }.min + ((SIZE * 2) - 5)
  platform.size.w = parts.sum { _1.size.w }
  
  platform
end

def make_rect(entity)
  { 
    x: entity.position.x,
    y: entity.position.y,
    w: entity.size.w,
    h: entity.size.h
  }
end

system :tick_timer do 
  state.timer.time.left -= (1 / 60)
  if state.timer.time.left <= 0
    delete_entity(state.player)
    create_entity(:player, {
      as: :player
    })
    state.timer.time.left = 10

    state.entities.select { has_components?(_1, :platform) }.each do 
      delete_entity(_1)
    end

    state.entities.select { has_components?(_1, :equation)}.each do 
      delete_entity(_1)
    end
  end
end

system :render_timer do 
  outputs.labels << {
    x: 1280 / 2,
    y: 0.from_top,
    text: state.timer.time.left.ceil,
    size_enum: 10, 
  }
end

system :manage_platforms, :platform do |entities|
  step = SIZE * 5

  num_platforms = entities.size / 6

  max_rendered = (state.player.max_height.y / step).ceil

  if max_rendered >= num_platforms
    3.times do |i|
      y = num_platforms + i + 1
      odd_even = [:odd, :even].shuffle
      make_platform(:left, step * y, odd_even.first)
      make_platform(:right, step * y, odd_even.second)
    end
  end
end

system :render_score do 
  l = layout.rect(row: 0, col: 0, w: 5, h: 1)
  outputs.labels << {
    x: l.x,
    y: l.y,
    text: "Score: #{state.player.max_height.y.to_i}"
  }
end

system :controls do 
  speed = 6

  if inputs.keyboard.key_down.space && has_components?(state.player, :on_ground)
    remove_component(state.player, :on_ground)
    state.player.accel.y += speed * 5
    outputs.sounds << "sounds/impactPlate_light_00#{rand.remap(0, 1, 0, 5).to_i}.ogg"
  end

  
  state.player.accel.x += inputs.keyboard.left_right * speed

  state.player.accel.x *= 0.79
end

system :acceleration, :accel do |entities|
  entities.each do |entity|
    entity.position.y += entity.accel.y
    entity.position.x += entity.accel.x
  end
end

system :render_sprites, :position, :size, :sprite do |entities|
  entities.each do |entity|
    outputs.sprites << {
      x: entity.position.x,
      y: entity == state.player ? SIZE : entity.position.y - state.player.position.y + SIZE,
      w: entity.size.w,
      h: entity.size.h,
      path: entity.sprite.path,
      tile_w: entity.sprite.tile_w,
      tile_h: entity.sprite.tile_h,
      tile_x: entity.sprite.tile_x,
      tile_y: entity.sprite.tile_y
    }
  end
end

system :render_equations, :equation do |entities|
  entities.each do |entity|
    # entity.position.y - state.player.position.y + SIZE
    outputs.labels << {
      x: entity.position.x,
      y: entity.position.y - state.player.position.y,
      w: entity.size.w,
      h: SIZE,
      size_enum: 0,
      text: entity.equation.equation,
      alignment_enum: 1,
      r: 0, g: 0, b: 0, a: 255,
    }
  end
end

system :gravity do |entities| 
  platforms = state.entities.select { has_components?(_1, :platform) || has_components?(_1, :floor) }

  next_pos = { x: state.player.position.x, y: state.player.position.y - SIZE, w: SIZE, h: SIZE }
    
  on_ground = platforms.find do 
    rect = make_rect(_1)
    has_intersection = rect.intersect_rect?(next_pos)
    is_odd = has_intersection && _1.parent&.parent&.equation&.answer&.odd?

    has_intersection && (is_odd || !_1.parent)
  end

  on_ground = make_rect(on_ground) if on_ground
  if on_ground && state.player.accel.y < 0
    state.player.accel.y = 0
    state.player.position.y = on_ground.y + SIZE
    
    outputs.sounds << "sounds/footstep_carpet_00#{rand.remap(0, 1, 0, 4).to_i}.ogg" unless has_components?(state.player, :on_ground)
    state.timer.time.left = 10 unless has_components?(state.player, :on_ground)

    add_component(state.player, :on_ground)

  elsif !on_ground
    state.player.accel.y -= 0.98
  end

  
  state.player.max_height.y = [state.player.position.y, state.player.max_height.y].max
end


def tick(args)
  if args.state.tick_count == 0 
    set_world(:default)
    args.audio[:bg_music] = { input: "sounds/Lo-Fi - Gentle Melancholy Loop.ogg", looping: true }
  end

  process_systems(args)
end
