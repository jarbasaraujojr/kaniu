export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/avaliacoes`);
  const data = await res.json();

  const container = document.getElementById("tab-avaliacoes");
  if (!data.length) {
    container.innerHTML = "<p>Nenhuma avaliação encontrada.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr>
          <th>Data</th>
          <th>Observação</th>
          <th>Veterinário</th>
          <th>Temperatura</th>
          <th>Score</th>
          <th>Peso</th>
          <th>Nota</th>
        </tr>
      </thead>
      <tbody>
        ${data.map(av => `
          <tr>
            <td>${av.data}</td>
            <td>${av.observacao || "-"}</td>
            <td>${av.veterinario_nome || "-"}</td>
            <td>${av.temperatura || "-"}</td>
            <td>${av.score || "-"}</td>
            <td>${av.peso ? av.peso + " kg" : "-"}</td>
            <td>${av.nota || "-"}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
