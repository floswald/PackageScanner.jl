import pickle

# Create ragged/nested data structure
ragged_data = {
    'arrays': [
        [1, 2, 3],           # length 3
        [4, 5],              # length 2
        [6, 7, 8, 9]         # length 4
    ],
    'nested_dict': {
        'names': ['Alice', 'Bob', 'Charlie'],
        'ages': [25, 30],    # different length!
        'addresses': {
            'Alice': '123 Main St',
            'Bob': '456 Oak Ave'
        }
    },
    'mixed_types': [
        [1, 2, 3],
        'a string',
        {'key': 'value'},
        [[1, 2], [3, 4, 5]]  # nested ragged
    ]
}

# Write to pickle file
with open('ragged_data.pkl', 'wb') as f:
    pickle.dump(ragged_data, f)

print("Created ragged_data.pkl")