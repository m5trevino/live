#!/usr/bin/env python3
import json
import os
import sys # Import sys to check platform and exit
# Try importing tkinter for the GUI option, but don't fail if it's not there
try:
    import tkinter as tk
    from tkinter import filedialog
    GUI_AVAILABLE = True
except ImportError:
    GUI_AVAILABLE = False
    # print("Warning: tkinter not found. GUI file picker is not available.") # Keep it quiet unless requested

# START ### FORMATTING FUNCTION ###
def format_conversation(json_string):
    """
    Parses a JSON string containing conversation chunks and formats it
    into a specific text layout.
    """
    try:
        data = json.loads(json_string)
        # Navigate safely to the chunks list, defaulting to empty list if keys are missing
        chunks = data.get('chunkedPrompt', {}).get('chunks', [])
    except json.JSONDecodeError as e:
        # Provide more context if possible
        print(f"Error decoding JSON: {e}", file=sys.stderr) # Print errors to stderr
        return f"Error decoding JSON: {e}"
    except AttributeError:
         print("Error: Input JSON structure is not as expected (missing 'chunkedPrompt' or 'chunks').", file=sys.stderr) # Print errors to stderr
         return "Error: Input JSON structure is not as expected (missing 'chunkedPrompt' or 'chunks')."


    output_parts = []

    for chunk in chunks:
        role = chunk.get('role')
        text = chunk.get('text', '') # Default to empty string if text is missing
        is_thought = chunk.get('isThought', False)

        # Skip chunks that are missing essential role or text
        if not role or text is None: # Check for None text too
            # print(f"Skipping chunk due to missing role or text: {chunk}", file=sys.stderr) # Optional: uncomment for noisy debug
            continue

        formatted_block = ""
        if role == 'user':
            formatted_block = f"""###user output starts###
{text}
above is from - user
###user output end###"""
        elif role == 'model':
            if is_thought:
                formatted_block = f"""###model thoughts starts###
{text}
above is the thoughts of the model
###model thoughts end###"""
            else:
                formatted_block = f"""###model output starts###
{text}
###model output end###"""
        else:
            # print(f"Skipping chunk with unexpected role: {role}", file=sys.stderr) # Optional: uncomment for noisy debug
            continue # Skip appending if role is unexpected

        if formatted_block:
             output_parts.append(formatted_block)

    # If no parts were processed, it means the input JSON was likely empty or malformed beyond basic checks
    if not output_parts and chunks:
         print("Warning: Processed chunks list was not empty, but no output blocks were generated. Input format may be unusual.", file=sys.stderr)
    elif not output_parts and not chunks:
         return "Warning: Input JSON contained no processable chunks."


    return "\n\n".join(output_parts)
# FINISH ### FORMATTING FUNCTION ###


# START ### FILE INPUT HANDLING ###
def get_input_filepath():
    """
    Prompts the user for a file path or uses a GUI file picker.
    Returns the chosen filepath or None on failure/cancel.
    """
    print("Enter the path to the JSON conversation file.")
    print("Alternatively, type 'gui' to use a file explorer (if available).")

    while True:
        user_input = input("File path or 'gui'> ").strip().lower()

        if user_input == 'gui':
            if GUI_AVAILABLE:
                # Create a dummy root window, hide it, and open file dialog
                root = tk.Tk()
                root.withdraw() # Hide the main window
                # *** MODIFIED filetypes pattern HERE ***
                filepath = filedialog.askopenfilename(
                    title="Select Conversation File",
                    filetypes=(("All files", "*"), ("JSON files", "*.json")) # Use "*" instead of "*.*" for All Files on Linux
                )
                root.destroy() # Clean up the dummy window
                if filepath:
                    return filepath
                else:
                    print("File selection cancelled. Please try again or enter a path.")
            else:
                print("GUI file picker not available. Please enter a file path.")
        else:
            # Assume user entered a path
            filepath = user_input
            if os.path.exists(filepath):
                 if os.path.isfile(filepath):
                      return filepath
                 else:
                      print(f"Error: '{filepath}' exists but is not a file. Please try again.")
            else:
                print(f"Error: File not found at '{filepath}'. Please try again.")

# FINISH ### FILE INPUT HANDLING ###


# START ### MAIN PROCESSING ###
input_filepath = get_input_filepath()

if not input_filepath:
    print("No file selected. Exiting.", file=sys.stderr)
    sys.exit(1) # Exit script if no file was chosen

input_json_string = None
formatted_output = None

try:
    # Read the JSON data from the file with explicit UTF-8 encoding
    # Use 'with' for automatic file closing
    with open(input_filepath, 'r', encoding='utf-8') as f:
        input_json_string = f.read()

except FileNotFoundError:
    # This case should ideally be caught by get_input_filepath, but double-check
    print(f"Error: File not found at '{input_filepath}'. Exiting.", file=sys.stderr)
    sys.exit(1)
except IOError as e:
    print(f"Error reading file '{input_filepath}': {e}. Exiting.", file=sys.stderr)
    sys.exit(1)
except Exception as e: # Catch any other file reading issues
    print(f"An unexpected error occurred while reading file '{input_filepath}': {e}. Exiting.", file=sys.stderr)
    sys.exit(1)


# Process the JSON string ONLY if it was read successfully
if input_json_string is not None:
    formatted_output = format_conversation(input_json_string)

# FINISH ### MAIN PROCESSING ###


# START ### FILE OUTPUT HANDLING ###
# Check if formatted_output is not None and doesn't contain the initial error message pattern from format_conversation
# Also check if it's not the "no chunks" warning
if formatted_output and not formatted_output.startswith("Error:") and not formatted_output.startswith("Warning:"):
    try:
        # Generate the output filename based on the input filename
        input_dir = os.path.dirname(input_filepath)
        input_basename = os.path.basename(input_filepath)
        # Handle potential lack of extension in input for output naming
        if '.' in input_basename:
             name, ext = os.path.splitext(input_basename)
        else:
             name = input_basename # Treat the whole name as the base if no extension
        output_filename = f"{name}-formatted.txt"
        output_filepath = os.path.join(input_dir, output_filename)

        # Ensure the output file name is not the same as input in a weird edge case
        if os.path.abspath(output_filepath) == os.path.abspath(input_filepath):
             output_filename = f"{name}-formatted_output.txt" # Use a different name
             output_filepath = os.path.join(input_dir, output_filename)
             print(f"Warning: Output filename clashed with input. Using '{output_filename}' instead.", file=sys.stderr)


        with open(output_filepath, 'w', encoding='utf-8') as f:
            f.write(formatted_output)
        print(f"\nFormatted conversation saved to '{output_filepath}'")

    except IOError as e:
        print(f"\nError writing to file '{output_filepath}': {e}", file=sys.stderr)
    except Exception as e:
         print(f"\nAn unexpected error occurred while writing output file: {e}", file=sys.stderr)
else:
    # If formatted_output was None, an error occurred earlier.
    # If it starts with "Error:" or "Warning:", that message was already printed by format_conversation
    # We can print a generic failure message or let the error propagate naturally
    if formatted_output is not None:
         # If it's a warning about no chunks, print it
         if formatted_output.startswith("Warning:"):
              print(formatted_output)
         else:
              # If it's an error message from format_conversation, it was already printed
              print("\nFormatting failed. Check error messages above.", file=sys.stderr)
    # If formatted_output was None, the reading failed, and error was already printed.
# FINISH ### FILE OUTPUT HANDLING ###
