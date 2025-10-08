export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/tratamentos`);
  const data = await res.json();

  const container = document.getElementById("tab-tratamentos");
  if (!data.length) {
    container.innerHTML = "<p>Nenhum tratamento encontrado.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr><th>Data</th><th>Veterinário</th><th>Medicamentos</th><th>Finalizado</th></tr>
      </thead>
      <tbody>
        ${data.map(tr => `
          <tr>
            <td>${tr.data}</td>
            <td>${tr.veterinario_nome || "-"}</td>
            <td>${Array.isArray(tr.medicamentos) ? tr.medicamentos.join(", ") : "-"}</td>
            <td>${tr.finalizada ? "Sim" : "Não"}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
