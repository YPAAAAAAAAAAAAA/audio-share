#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

# Create a clean 1200x630 preview image without Chinese characters
def create_preview_image():
    # Image dimensions for Open Graph
    width, height = 1200, 630
    
    # Create image with white background
    img = Image.new('RGB', (width, height), 'white')
    draw = ImageDraw.Draw(img)
    
    # Draw black border
    border_width = 8
    draw.rectangle([0, 0, width-1, height-1], outline='black', width=border_width)
    
    # Draw centered play button (smaller circle with triangle)
    center_x, center_y = width // 2, height // 2
    button_radius = 60
    
    # Draw play button circle
    draw.ellipse([
        center_x - button_radius, center_y - button_radius,
        center_x + button_radius, center_y + button_radius
    ], fill='black', outline='black')
    
    # Draw play triangle inside circle
    triangle_size = 30
    triangle_points = [
        (center_x - triangle_size//2 + 8, center_y - triangle_size//2),
        (center_x - triangle_size//2 + 8, center_y + triangle_size//2),
        (center_x + triangle_size//2 + 8, center_y)
    ]
    draw.polygon(triangle_points, fill='white')
    
    # Draw simple waveform below play button
    waveform_y = center_y + button_radius + 60
    waveform_width = 400
    waveform_start_x = center_x - waveform_width // 2
    
    # Draw waveform bars
    bar_width = 6
    bar_gap = 4
    num_bars = waveform_width // (bar_width + bar_gap)
    
    import random
    random.seed(42)  # Consistent pattern
    
    for i in range(num_bars):
        bar_x = waveform_start_x + i * (bar_width + bar_gap)
        bar_height = random.randint(10, 60)
        bar_y = waveform_y - bar_height // 2
        
        draw.rectangle([
            bar_x, bar_y,
            bar_x + bar_width, bar_y + bar_height
        ], fill='black')
    
    # Remove text - clean minimal design
    
    # Save the image
    output_path = '/Users/li/Desktop/audios/clean-preview.png'
    img.save(output_path, 'PNG')
    print(f"Preview image saved to {output_path}")

if __name__ == "__main__":
    create_preview_image()